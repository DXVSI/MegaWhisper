#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $# -ne 6 ]]; then
    echo "usage: $0 RECOVERY_DIR REPO_DIR SITE_DIR EXPECTED_FINGERPRINT EXPECTED_RUN_ID strict|manifest" >&2
    exit 64
fi

recovery_dir="$(realpath "$1")"
repo_dir="$(realpath -m "$2")"
site_dir="$(realpath -m "$3")"
readonly expected_fingerprint="${4^^}"
readonly expected_run_id="$5"
readonly site_validation_mode="$6"
readonly recovery_dir repo_dir site_dir
readonly archive_name="MegaWhisper-flatpak-repo.tar.zst"
readonly site_archive_name="MegaWhisper-pages-site.tar.zst"
readonly metadata_name="flatpak-pages-recovery.txt"
readonly key_name="megawhisper-release-key.asc"

if [[ ! "$expected_fingerprint" =~ ^([0-9A-F]{40}|[0-9A-F]{64})$ ]]; then
    echo "expected fingerprint must be a 40 or 64 character hexadecimal value" >&2
    exit 64
fi
if [[ ! "$expected_run_id" =~ ^[1-9][0-9]*$ ]]; then
    echo "expected run ID must be a positive integer" >&2
    exit 64
fi
if [[ "$site_validation_mode" != strict \
      && "$site_validation_mode" != manifest ]]; then
    echo "site validation mode must be strict or manifest" >&2
    exit 64
fi
for file_name in \
    "$archive_name" "$archive_name.asc" \
    "$site_archive_name" "$site_archive_name.asc" \
    "$metadata_name" "$metadata_name.asc" "$key_name"; do
    if [[ ! -f "$recovery_dir/$file_name" || -L "$recovery_dir/$file_name" \
          || ! -s "$recovery_dir/$file_name" ]]; then
        echo "required regular recovery file is missing: $file_name" >&2
        exit 66
    fi
done
if [[ -e "$repo_dir" ]] \
    && [[ -n "$(find "$repo_dir" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
    echo "recovery repository destination must be empty: $repo_dir" >&2
    exit 73
fi
if [[ -e "$site_dir" ]] \
    && [[ -n "$(find "$site_dir" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
    echo "recovery site destination must be empty: $site_dir" >&2
    exit 73
fi

gpg_home="$(mktemp -d)"
state_root="$(mktemp -d)"
cleanup() {
    gpgconf --homedir "$gpg_home" --kill all >/dev/null 2>&1 || true
    rm -rf "$gpg_home" "$state_root"
}
trap cleanup EXIT
chmod 0700 "$gpg_home" "$state_root"

mapfile -t public_fingerprints < <(
    gpg --batch --with-colons --show-keys "$recovery_dir/$key_name" \
        | awk -F: '
            $1 == "pub" { want_primary=1; next }
            $1 == "fpr" && want_primary { print toupper($10); want_primary=0 }
          '
)
if [[ "${#public_fingerprints[@]}" -ne 1 \
      || "${public_fingerprints[0]}" != "$expected_fingerprint" ]]; then
    echo "recovery public key does not match the pinned fingerprint" >&2
    exit 65
fi
gpg --batch --homedir "$gpg_home" --import "$recovery_dir/$key_name"
gpg --batch --homedir "$gpg_home" \
    --verify "$recovery_dir/$archive_name.asc" "$recovery_dir/$archive_name"
gpg --batch --homedir "$gpg_home" \
    --verify "$recovery_dir/$site_archive_name.asc" \
    "$recovery_dir/$site_archive_name"
gpg --batch --homedir "$gpg_home" \
    --verify "$recovery_dir/$metadata_name.asc" "$recovery_dir/$metadata_name"

declare -A metadata=()
while IFS='=' read -r key value; do
    if [[ -z "$key" || -z "$value" || -n "${metadata[$key]+present}" ]]; then
        echo "invalid or duplicate recovery metadata field: $key" >&2
        exit 65
    fi
    case "$key" in
        format|source_run_id|source_sha|public_source_sha|release_repository|\
        version|flatpak_commit|archive_sha256|site_source_sha|\
        site_archive_sha256|rollback_commit|rollback_archive_sha256|\
        rollback_site_source_sha|rollback_site_archive_sha256)
            metadata[$key]="$value"
            ;;
        *)
            echo "unknown recovery metadata field: $key" >&2
            exit 65
            ;;
    esac
done < "$recovery_dir/$metadata_name"

for key in format source_run_id source_sha public_source_sha \
    release_repository version flatpak_commit archive_sha256 \
    site_source_sha site_archive_sha256 rollback_commit \
    rollback_archive_sha256 rollback_site_source_sha \
    rollback_site_archive_sha256; do
    if [[ -z "${metadata[$key]+present}" ]]; then
        echo "required recovery metadata field is missing: $key" >&2
        exit 65
    fi
done
if [[ "${metadata[format]}" != 3 \
      || "${metadata[source_run_id]}" != "$expected_run_id" \
      || ! "${metadata[source_sha]}" =~ ^[0-9a-f]{40}$ \
      || ! "${metadata[public_source_sha]}" =~ ^[0-9a-f]{40}$ \
      || ! "${metadata[release_repository]}" \
          =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ \
      || ! "${metadata[version]}" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ \
      || ! "${metadata[flatpak_commit]}" =~ ^[0-9a-f]{64}$ \
      || ! "${metadata[archive_sha256]}" =~ ^[0-9a-f]{64}$ \
      || ! "${metadata[site_source_sha]}" =~ ^[0-9a-f]{40}$ \
      || ! "${metadata[site_archive_sha256]}" =~ ^[0-9a-f]{64}$ \
      || ! "${metadata[rollback_commit]}" =~ ^(none|[0-9a-f]{64})$ \
      || ! "${metadata[rollback_archive_sha256]}" =~ ^[0-9a-f]{64}$ \
      || ! "${metadata[rollback_site_source_sha]}" =~ ^[0-9a-f]{40}$ \
      || ! "${metadata[rollback_site_archive_sha256]}" \
          =~ ^[0-9a-f]{64}$ ]]; then
    echo "signed recovery metadata has invalid values" >&2
    exit 65
fi
actual_archive_sha256="$(sha256sum "$recovery_dir/$archive_name" | awk '{print $1}')"
if [[ "$actual_archive_sha256" != "${metadata[archive_sha256]}" ]]; then
    echo "recovery archive checksum does not match signed metadata" >&2
    exit 65
fi
actual_site_archive_sha256="$(
    sha256sum "$recovery_dir/$site_archive_name" | awk '{print $1}'
)"
if [[ "$actual_site_archive_sha256" != "${metadata[site_archive_sha256]}" ]]; then
    echo "recovery site archive checksum does not match signed metadata" >&2
    exit 65
fi

while IFS= read -r entry; do
    case "$entry" in
        /*|..|../*|*/../*)
            echo "unsafe path in recovery archive: $entry" >&2
            exit 65
            ;;
    esac
done < <(tar --zstd --list --file "$recovery_dir/$archive_name")
mkdir -p "$repo_dir"
tar --zstd --extract --file "$recovery_dir/$archive_name" \
    --directory "$repo_dir" --no-same-owner --no-same-permissions
ostree fsck --repo="$repo_dir"

while IFS= read -r entry; do
    case "$entry" in
        /*|..|../*|*/../*)
            echo "unsafe path in recovery site archive: $entry" >&2
            exit 65
            ;;
    esac
done < <(tar --zstd --list --file "$recovery_dir/$site_archive_name")
mkdir -p "$site_dir"
tar --zstd --extract --file "$recovery_dir/$site_archive_name" \
    --directory "$site_dir" --no-same-owner --no-same-permissions
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$script_dir/verify-pages-site.sh" \
    "$site_dir" release "$site_validation_mode"

readonly app_ref="app/io.github.dxvsi.megawhisper/x86_64/stable"
repo_commit="$(ostree rev-parse --repo="$repo_dir" "$app_ref")"
if [[ "$repo_commit" != "${metadata[flatpak_commit]}" ]]; then
    echo "recovery repository head does not match signed metadata" >&2
    exit 65
fi

export XDG_DATA_HOME="$state_root/data"
export XDG_CONFIG_HOME="$state_root/config"
export XDG_CACHE_HOME="$state_root/cache"
mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
flatpak remote-add --user \
    --gpg-import="$recovery_dir/$key_name" \
    megawhisper-recovery-local "file://$repo_dir"
verified_commit="$(flatpak remote-info --user --show-commit \
    megawhisper-recovery-local io.github.dxvsi.megawhisper)"
if [[ "$verified_commit" != "${metadata[flatpak_commit]}" ]]; then
    echo "Flatpak signature verification returned an unexpected commit" >&2
    exit 65
fi

echo "Signed Pages recovery payload verified for commit $verified_commit"
