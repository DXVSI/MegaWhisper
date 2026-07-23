#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $# -ne 7 ]]; then
    echo "usage: $0 RELEASE_REPOSITORY RELEASE_TAG BASE_URL EXPECTED_FINGERPRINT SOURCE_SITE_DIR SOURCE_IMAGE_DIR WORK_DIR" >&2
    exit 64
fi

readonly release_repository="$1"
readonly release_tag="$2"
readonly base_url="${3%/}"
readonly expected_fingerprint="${4^^}"
source_site_dir="$(realpath "$5")"
source_image_dir="$(realpath "$6")"
work_dir="$(realpath -m "$7")"
readonly source_site_dir source_image_dir work_dir

if [[ ! "$release_repository" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ \
      || ! "$release_tag" \
          =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ \
      || ! "$base_url" \
          =~ ^https://[A-Za-z0-9.-]+(:[0-9]+)?(/[A-Za-z0-9._~!$\&\(\)*+,\;=:@%/-]*)?$ \
      || ! "$expected_fingerprint" =~ ^([0-9A-F]{40}|[0-9A-F]{64})$ ]]; then
    echo "Pages site refresh identity is invalid" >&2
    exit 64
fi
if [[ ! -d "$source_site_dir" || -L "$source_site_dir" \
      || ! -d "$source_image_dir" || -L "$source_image_dir" ]]; then
    echo "Pages site refresh source directories are invalid" >&2
    exit 66
fi
if [[ -e "$work_dir" ]] \
    && [[ -n "$(find "$work_dir" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
    echo "Pages site refresh work directory must be empty: $work_dir" >&2
    exit 73
fi

for command_name in awk cmp curl find flatpak git gh gpg gpgconf install jq \
    mkdir mktemp mv node ostree realpath rm sha256sum sort stat tar xmllint \
    zstd; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        echo "required command not found: $command_name" >&2
        exit 69
    fi
done

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly script_dir
readonly version="${release_tag#v}"
expected_release_assets="$("$script_dir/list-release-assets.sh" \
    "$version" release)"
readonly expected_release_assets

mkdir -p "$work_dir/release-assets"
release_json="$(gh api \
    --header 'Accept: application/vnd.github+json' \
    --header 'X-GitHub-Api-Version: 2026-03-10' \
    "repos/$release_repository/releases/tags/$release_tag")"
latest_release_json="$(gh api \
    --header 'Accept: application/vnd.github+json' \
    --header 'X-GitHub-Api-Version: 2026-03-10' \
    "repos/$release_repository/releases/latest")"
if ! jq -e --arg tag "$release_tag" '
    (.id | type) == "number" and .id > 0
    and .tag_name == $tag
    and .draft == false
    and .prerelease == false
    and (.target_commitish | type) == "string"
    and (.assets | length) == 10
    and all(.assets[];
      (.id | type) == "number" and .id > 0
      and (.name | type) == "string"
      and (.name | test("^[A-Za-z0-9][A-Za-z0-9._+-]*$"))
      and .state == "uploaded"
      and (.size | type) == "number" and .size > 0
      and (.digest | type) == "string"
      and (.digest | test("^sha256:[0-9a-f]{64}$")))
  ' <<< "$release_json" >/dev/null; then
    echo "selected release identity or asset metadata is invalid" >&2
    exit 65
fi
release_id="$(jq -r '.id' <<< "$release_json")"
latest_release_id="$(jq -r '.id // empty' <<< "$latest_release_json")"
if [[ "$latest_release_id" != "$release_id" ]]; then
    echo "selected release is not the exact latest stable release" >&2
    exit 65
fi
actual_release_assets="$(jq -r '.assets[].name' <<< "$release_json" \
    | LC_ALL=C sort)"
if [[ "$actual_release_assets" != "$expected_release_assets" ]]; then
    echo "selected release asset inventory is not exact" >&2
    exit 65
fi

download_asset() {
    local asset_name="$1"
    local asset_json asset_id asset_size asset_digest asset_path candidate
    asset_json="$(jq -c --arg name "$asset_name" '
        [.assets[] | select(.name == $name)]
        | if length == 1 then .[0] else empty end
      ' <<< "$release_json")"
    if [[ -z "$asset_json" ]]; then
        echo "release asset is missing or ambiguous: $asset_name" >&2
        exit 65
    fi
    asset_id="$(jq -r '.id' <<< "$asset_json")"
    asset_size="$(jq -r '.size' <<< "$asset_json")"
    asset_digest="$(jq -r '.digest' <<< "$asset_json")"
    asset_path="$work_dir/release-assets/$asset_name"
    candidate="$asset_path.part"
    for attempt in 1 2 3; do
        echo "Downloading $asset_name, attempt $attempt of 3"
        rm -f "$candidate"
        if gh api --header 'Accept: application/octet-stream' \
              "repos/$release_repository/releases/assets/$asset_id" \
              > "$candidate" \
            && [[ "$(stat -c '%s' "$candidate")" == "$asset_size" ]] \
            && [[ "sha256:$(sha256sum "$candidate" | awk '{print $1}')" \
                == "$asset_digest" ]]; then
            mv "$candidate" "$asset_path"
            return
        fi
    done
    rm -f "$candidate"
    echo "release asset remained unavailable or invalid: $asset_name" >&2
    exit 69
}

readonly recovery_bundle_name="MegaWhisper-$version-recovery.tar.zst"
for asset_name in \
    "$recovery_bundle_name" \
    SHA256SUMS \
    SHA256SUMS.asc \
    megawhisper-release-key.asc; do
    download_asset "$asset_name"
done

gpg_home="$(mktemp -d)"
readonly gpg_home
cleanup() {
    gpgconf --homedir "$gpg_home" --kill all >/dev/null 2>&1 || true
    rm -rf "$gpg_home"
}
trap cleanup EXIT
chmod 0700 "$gpg_home"
mapfile -t release_fingerprints < <(
    gpg --batch --with-colons --show-keys \
        "$work_dir/release-assets/megawhisper-release-key.asc" \
        | awk -F: '
            $1 == "pub" { want_primary=1; next }
            $1 == "fpr" && want_primary {
                print toupper($10)
                want_primary=0
            }
          '
)
if [[ "${#release_fingerprints[@]}" -ne 1 \
      || "${release_fingerprints[0]}" != "$expected_fingerprint" ]]; then
    echo "release key does not match the pinned fingerprint" >&2
    exit 65
fi
gpg --batch --homedir "$gpg_home" \
    --import "$work_dir/release-assets/megawhisper-release-key.asc"
gpg --batch --homedir "$gpg_home" --verify \
    "$work_dir/release-assets/SHA256SUMS.asc" \
    "$work_dir/release-assets/SHA256SUMS"

checksum_names="$(awk '
    NF != 2 || $1 !~ /^[0-9a-f]{64}$/ || substr($2, 1, 1) != "*" {
        exit 65
    }
    {
        name=substr($2, 2)
        if (name == "" || name ~ /\// || name ~ /^\./) exit 65
        print name
    }
  ' "$work_dir/release-assets/SHA256SUMS" | LC_ALL=C sort)" || {
    echo "signed checksum list contains an invalid entry" >&2
    exit 65
}
expected_checksum_names="$("$script_dir/list-release-assets.sh" \
    "$version" payload)"
if [[ "$checksum_names" != "$expected_checksum_names" ]]; then
    echo "signed checksum inventory does not match binary-v1" >&2
    exit 65
fi

verify_signed_checksum() {
    local file_name="$1"
    local expected_checksum actual_checksum
    expected_checksum="$(awk -v target="*$file_name" '
        $2 == target { count++; value=$1 }
        END { if (count == 1) print value }
      ' "$work_dir/release-assets/SHA256SUMS")"
    actual_checksum="$(sha256sum "$work_dir/release-assets/$file_name" \
        | awk '{print $1}')"
    if [[ ! "$expected_checksum" =~ ^[0-9a-f]{64}$ \
          || "$actual_checksum" != "$expected_checksum" ]]; then
        echo "release asset differs from the signed checksum: $file_name" >&2
        exit 65
    fi
}
verify_signed_checksum "$recovery_bundle_name"
verify_signed_checksum megawhisper-release-key.asc

"$script_dir/release-bundles.sh" extract recovery "$version" \
    "$work_dir/release-assets/$recovery_bundle_name" \
    "$work_dir/recovery"
if ! cmp --silent \
    "$work_dir/release-assets/megawhisper-release-key.asc" \
    "$work_dir/recovery/megawhisper-release-key.asc"; then
    echo "top-level and recovery release keys differ" >&2
    exit 65
fi

recovery_metadata="$work_dir/recovery/flatpak-pages-recovery.txt"
metadata_value() {
    local key="$1"
    awk -F= -v key="$key" '
        $1 == key { count++; value=$2 }
        END { if (count == 1) print value }
      ' "$recovery_metadata"
}
producer_run_id="$(metadata_value producer_run_id)"
metadata_repository="$(metadata_value release_repository)"
metadata_version="$(metadata_value version)"
flatpak_commit="$(metadata_value flatpak_commit)"
distribution_sha="$(metadata_value distribution_sha)"
release_target="$(jq -r '.target_commitish' <<< "$release_json")"
if [[ ! "$producer_run_id" =~ ^[1-9][0-9]*$ \
      || "$metadata_repository" != "$release_repository" \
      || "$metadata_version" != "$version" \
      || ! "$flatpak_commit" =~ ^[0-9a-f]{64}$ \
      || ! "$distribution_sha" =~ ^[0-9a-f]{40}$ \
      || "$release_target" != "$distribution_sha" ]]; then
    echo "signed recovery metadata does not match the selected release" >&2
    exit 65
fi
public_tag_sha="$(git ls-remote --refs \
    "https://github.com/$release_repository.git" "refs/tags/$release_tag" \
    | awk -v ref="refs/tags/$release_tag" '
        $2 == ref { count++; value=$1 }
        END { if (count == 1) print value }
      ')"
if [[ "$public_tag_sha" != "$distribution_sha" ]] \
    || ! git merge-base --is-ancestor "$distribution_sha" HEAD; then
    echo "release tag is not an immutable ancestor of the checked-out main branch" >&2
    exit 65
fi

"$script_dir/verify-pages-recovery.sh" \
    "$work_dir/recovery" \
    "$work_dir/baseline-repo" \
    "$work_dir/baseline-site" \
    "$expected_fingerprint" \
    "$producer_run_id" manifest
"$script_dir/verify-flatpak-release-repo.sh" \
    "$work_dir/baseline-repo" stable
install -m 0644 "$recovery_metadata" \
    "$work_dir/baseline-repo/flatpak-active-state.txt"
install -m 0644 "$recovery_metadata.asc" \
    "$work_dir/baseline-repo/flatpak-active-state.txt.asc"
install -m 0644 "$work_dir/recovery/megawhisper-release-key.asc" \
    "$work_dir/baseline-repo/megawhisper-release-key.asc"
"$script_dir/stage-pages-site-refresh.sh" \
    "$source_site_dir" "$source_image_dir" \
    "$work_dir/baseline-site" "$work_dir/desired-site"
"$script_dir/assemble-pages-state.sh" \
    "$work_dir/desired-site" "$work_dir/baseline-repo" \
    "$work_dir/desired-pages" "$flatpak_commit" release
"$script_dir/assemble-pages-state.sh" \
    "$work_dir/baseline-site" "$work_dir/baseline-repo" \
    "$work_dir/baseline-pages" "$flatpak_commit" release

prepare_previous_refresh_state() {
    local runs_json previous_sha previous_source previous_site previous_pages
    if ! runs_json="$(gh api --method GET \
          "repos/$release_repository/actions/workflows/pages-site-refresh.yml/runs" \
          -f branch=main \
          -f event=workflow_dispatch \
          -f status=success \
          -F per_page=100)"; then
        echo "Previous successful Pages refresh state is unavailable" >&2
        return 1
    fi
    previous_sha="$(jq -r '
        [
          .workflow_runs[]
          | select(
              .event == "workflow_dispatch"
              and .status == "completed"
              and .conclusion == "success"
              and .head_branch == "main"
              and .path == ".github/workflows/pages-site-refresh.yml"
              and (.head_sha | type) == "string"
              and (.head_sha | test("^[0-9a-f]{40}$"))
            )
        ]
        | if length > 0 then .[0].head_sha else empty end
      ' <<< "$runs_json")"
    if [[ ! "$previous_sha" =~ ^[0-9a-f]{40}$ ]] \
        || ! git merge-base --is-ancestor "$previous_sha" HEAD; then
        echo "Previous successful Pages refresh is not a trusted main ancestor" >&2
        return 1
    fi

    previous_source="$work_dir/previous-source"
    previous_site="$work_dir/previous-site"
    previous_pages="$work_dir/previous-pages"
    mkdir -p "$previous_source" "$previous_site"
    if ! git archive "$previous_sha" -- site img \
          | tar -x -C "$previous_source"; then
        echo "Could not extract the previous Pages refresh source" >&2
        return 1
    fi
    if [[ ! -d "$previous_source/site" \
          || -L "$previous_source/site" \
          || ! -d "$previous_source/img" \
          || -L "$previous_source/img" \
          || -e "$previous_source/site/site-manifest.sha256" ]]; then
        echo "Previous Pages refresh source has an invalid layout" >&2
        return 1
    fi
    cp -a "$previous_source/site/." "$previous_site/"
    cp -a "$previous_source/img" "$previous_site/img"
    for file_name in \
        io.github.dxvsi.megawhisper.flatpakref \
        io.github.dxvsi.megawhisper.flatpakrepo; do
        install -m 0644 \
            "$work_dir/baseline-site/$file_name" \
            "$previous_site/$file_name"
    done
    (
        cd "$previous_site"
        while IFS= read -r -d '' file_name; do
            sha256sum -- "$file_name"
        done < <(
            find . -type f ! -name site-manifest.sha256 \
                -printf '%P\0' | LC_ALL=C sort -z
        )
    ) > "$previous_site/site-manifest.sha256"
    "$script_dir/verify-pages-site.sh" \
        "$previous_site" release manifest
    "$script_dir/assemble-pages-state.sh" \
        "$previous_site" "$work_dir/baseline-repo" \
        "$previous_pages" "$flatpak_commit" release
}

run_token="refresh-${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}"
if "$script_dir/verify-live-pages-state.sh" \
      "$base_url" "$work_dir/desired-pages" "$work_dir/desired-site" \
      "$expected_fingerprint" "$flatpak_commit" \
      "$run_token-desired" release; then
    refresh_mode=reconciled
elif "$script_dir/verify-live-pages-state.sh" \
      "$base_url" "$work_dir/baseline-pages" "$work_dir/baseline-site" \
      "$expected_fingerprint" "$flatpak_commit" \
      "$run_token-baseline" release; then
    refresh_mode=deploy
elif prepare_previous_refresh_state \
      && "$script_dir/verify-live-pages-state.sh" \
          "$base_url" "$work_dir/previous-pages" "$work_dir/previous-site" \
          "$expected_fingerprint" "$flatpak_commit" \
          "$run_token-previous" release; then
    refresh_mode=deploy
else
    echo "Live Pages state is not desired, signed baseline, or the exact previous successful refresh" >&2
    exit 65
fi

{
    printf 'mode=%s\n' "$refresh_mode"
    printf 'version=%s\n' "$version"
    printf 'source_sha=%s\n' "$(git rev-parse 'HEAD^{commit}')"
    printf 'fingerprint=%s\n' "$expected_fingerprint"
    printf 'flatpak_commit=%s\n' "$flatpak_commit"
} > "$work_dir/refresh-state.env"

echo "Prepared Pages site refresh: mode=$refresh_mode commit=$flatpak_commit"
