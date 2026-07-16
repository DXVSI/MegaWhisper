#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $# -ne 5 ]]; then
    echo "usage: $0 REPOSITORY_URL EXPECTED_STATE_DIR EXPECTED_FINGERPRINT EXPECTED_COMMIT CACHE_NONCE" >&2
    exit 64
fi

readonly repository_url="${1%/}"
expected_state_dir="$(realpath "$2")"
readonly expected_state_dir
readonly expected_fingerprint="${3^^}"
readonly expected_commit="$4"
readonly cache_nonce="$5"

if [[ ! "$repository_url" =~ ^https:// ]]; then
    echo "repository URL must use HTTPS" >&2
    exit 64
fi
if [[ ! "$expected_fingerprint" =~ ^([0-9A-F]{40}|[0-9A-F]{64})$ ]]; then
    echo "expected fingerprint must be a 40 or 64 character hexadecimal value" >&2
    exit 64
fi
if [[ ! "$cache_nonce" =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "cache nonce contains unsupported characters" >&2
    exit 64
fi
for command_name in awk cmp curl flatpak gpg gpgconf ostree realpath; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        echo "required command not found: $command_name" >&2
        exit 69
    fi
done

readonly -a repository_files=(summary summary.sig)
readonly -a marker_files=(
    flatpak-active-state.txt
    flatpak-active-state.txt.asc
)
for file_name in "${repository_files[@]}"; do
    if [[ ! -f "$expected_state_dir/$file_name" \
          || -L "$expected_state_dir/$file_name" \
          || ! -s "$expected_state_dir/$file_name" ]]; then
        echo "expected repository file is missing: $file_name" >&2
        exit 66
    fi
done

expected_marker_files=0
for file_name in "${marker_files[@]}"; do
    if [[ -f "$expected_state_dir/$file_name" \
          && ! -L "$expected_state_dir/$file_name" \
          && -s "$expected_state_dir/$file_name" ]]; then
        ((expected_marker_files += 1))
    elif [[ -e "$expected_state_dir/$file_name" || -L "$expected_state_dir/$file_name" ]]; then
        echo "expected marker entry is not a non-empty regular file: $file_name" >&2
        exit 66
    fi
done
if [[ "$expected_marker_files" -ne 0 && "$expected_marker_files" -ne 2 ]]; then
    echo "expected active-state marker pair is incomplete" >&2
    exit 65
fi
if [[ ! -f "$expected_state_dir/megawhisper-release-key.asc" \
      || -L "$expected_state_dir/megawhisper-release-key.asc" \
      || ! -s "$expected_state_dir/megawhisper-release-key.asc" ]]; then
    echo "expected release public key is missing" >&2
    exit 66
fi
if [[ "$expected_marker_files" -eq 2 ]]; then
    if [[ ! "$expected_commit" =~ ^[0-9a-f]{64}$ ]]; then
        echo "expected active commit has an invalid format" >&2
        exit 64
    fi
elif [[ -n "$expected_commit" ]]; then
    echo "an empty active state cannot declare an application commit" >&2
    exit 64
fi

work_dir="$(mktemp -d)"
readonly work_dir
cleanup() {
    if [[ -d "$work_dir/gnupg" ]]; then
        gpgconf --homedir "$work_dir/gnupg" --kill all >/dev/null 2>&1 || true
    fi
    rm -rf "$work_dir"
}
trap cleanup EXIT

download_live_file() {
    local file_name="$1"
    local output_path="$2"
    curl --silent --show-error --location \
        --proto '=https' --tlsv1.2 \
        --retry 3 --retry-all-errors --retry-delay 1 \
        --connect-timeout 10 --max-time 60 \
        --header 'Cache-Control: no-cache' \
        --output "$output_path" \
        --write-out '%{http_code}' \
        "$repository_url/$file_name?megawhisper_state=$cache_nonce"
}

for file_name in "${repository_files[@]}"; do
    status="$(download_live_file "$file_name" "$work_dir/$file_name")"
    if [[ "$status" != 200 || ! -s "$work_dir/$file_name" ]]; then
        echo "unable to download live repository file $file_name: HTTP $status" >&2
        exit 69
    fi
    if ! cmp --silent "$expected_state_dir/$file_name" "$work_dir/$file_name"; then
        echo "live repository file differs from expected bytes: $file_name" >&2
        exit 65
    fi
done

for file_name in "${marker_files[@]}"; do
    status="$(download_live_file "$file_name" "$work_dir/$file_name")"
    if [[ "$expected_marker_files" -eq 0 ]]; then
        if [[ "$status" != 404 ]]; then
            echo "live repository unexpectedly exposes $file_name: HTTP $status" >&2
            exit 65
        fi
        continue
    fi
    if [[ "$status" != 200 || ! -s "$work_dir/$file_name" ]]; then
        echo "unable to download live active-state file $file_name: HTTP $status" >&2
        exit 69
    fi
    if ! cmp --silent "$expected_state_dir/$file_name" "$work_dir/$file_name"; then
        echo "live active-state file differs from expected bytes: $file_name" >&2
        exit 65
    fi
done
key_status="$(download_live_file megawhisper-release-key.asc \
    "$work_dir/megawhisper-release-key.asc")"
if [[ "$key_status" != 200 \
      || ! -s "$work_dir/megawhisper-release-key.asc" ]]; then
    echo "unable to download live release public key: HTTP $key_status" >&2
    exit 69
fi
if ! cmp --silent "$expected_state_dir/megawhisper-release-key.asc" \
    "$work_dir/megawhisper-release-key.asc"; then
    echo "live release public key differs from expected bytes" >&2
    exit 65
fi

mapfile -t public_fingerprints < <(
    gpg --batch --with-colons --show-keys \
        "$work_dir/megawhisper-release-key.asc" \
        | awk -F: '
            $1 == "pub" { want_primary=1; next }
            $1 == "fpr" && want_primary { print toupper($10); want_primary=0 }
          '
)
if [[ "${#public_fingerprints[@]}" -ne 1 \
      || "${public_fingerprints[0]}" != "$expected_fingerprint" ]]; then
    echo "live release key does not match the pinned fingerprint" >&2
    exit 65
fi
mkdir -m 0700 "$work_dir/gnupg"
gpg --batch --homedir "$work_dir/gnupg" \
    --import "$work_dir/megawhisper-release-key.asc" >/dev/null

export HOME="$work_dir/flatpak-home"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_CACHE_HOME="$HOME/.cache"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_RUNTIME_DIR="$HOME/runtime"
install -d -m 0700 "$HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME" \
    "$XDG_CONFIG_HOME" "$XDG_RUNTIME_DIR"
flatpak remote-add --user \
    --gpg-import="$work_dir/megawhisper-release-key.asc" \
    megawhisper-live "$repository_url"

if [[ "$expected_marker_files" -eq 0 ]]; then
    signed_repo="$work_dir/signed-empty-repo"
    ostree init --repo="$signed_repo" --mode=archive-z2 >/dev/null
    install -m 0644 "$work_dir/summary" "$signed_repo/summary"
    install -m 0644 "$work_dir/summary.sig" "$signed_repo/summary.sig"
    flatpak remote-add --user \
        --gpg-import="$work_dir/megawhisper-release-key.asc" \
        signed-empty "file://$signed_repo"
    remote_refs="$(flatpak remote-ls --user --columns=ref signed-empty)"
    if [[ -n "$remote_refs" ]]; then
        echo "signed empty repository unexpectedly exposes Flatpak refs" >&2
        exit 65
    fi
    live_remote_refs="$(flatpak remote-ls --user --columns=ref \
        megawhisper-live)"
    if [[ -n "$live_remote_refs" ]]; then
        echo "live empty repository unexpectedly exposes Flatpak refs" >&2
        exit 65
    fi
    echo "Live signed empty Flatpak state matches the expected repository bytes"
    exit 0
fi

gpg --batch --homedir "$work_dir/gnupg" \
    --verify "$work_dir/flatpak-active-state.txt.asc" \
    "$work_dir/flatpak-active-state.txt"

marker_commit="$(awk -F= '
    $1 == "flatpak_commit" { count++; value=$2 }
    END { if (count == 1) print value }
  ' "$work_dir/flatpak-active-state.txt")"
if [[ "$marker_commit" != "$expected_commit" ]]; then
    echo "live signed marker does not identify the expected Flatpak commit" >&2
    exit 65
fi

live_commit="$(flatpak remote-info --user --show-commit \
    megawhisper-live io.github.dxvsi.megawhisper)"
if [[ "$live_commit" != "$expected_commit" ]]; then
    echo "live Flatpak client resolved an unexpected commit" >&2
    exit 65
fi

echo "Live signed Flatpak state verified for commit $expected_commit"
