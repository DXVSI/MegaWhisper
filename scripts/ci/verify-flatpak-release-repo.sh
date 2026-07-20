#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $# -ne 2 ]]; then
    echo "usage: $0 REPO_DIR stable|empty" >&2
    exit 64
fi

repo_dir="$(realpath "$1")"
readonly repo_dir
readonly expected_state="$2"
if [[ "$expected_state" != stable && "$expected_state" != empty ]]; then
    echo "Flatpak repository state must be stable or empty" >&2
    exit 64
fi
for command_name in awk grep mktemp ostree realpath rm sort; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        echo "required command not found: $command_name" >&2
        exit 69
    fi
done
if [[ ! -d "$repo_dir" || -L "$repo_dir" || ! -f "$repo_dir/config" ]]; then
    echo "Flatpak release repository is missing or unsafe: $repo_dir" >&2
    exit 66
fi

readonly release_ref=app/io.github.dxvsi.megawhisper/x86_64/stable
mapfile -t repository_refs < <(
    ostree refs --repo="$repo_dir" | LC_ALL=C sort
)
release_ref_count=0
for repository_ref in "${repository_refs[@]}"; do
    case "$repository_ref" in
        "$release_ref")
            release_ref_count=$((release_ref_count + 1))
            ;;
        appstream/x86_64|appstream2/x86_64)
            ;;
        *)
            echo "Flatpak release repository contains a forbidden ref: $repository_ref" >&2
            exit 65
            ;;
    esac
done
if [[ "$expected_state" == stable ]]; then
    if [[ "$release_ref_count" -ne 1 ]]; then
        echo "Flatpak release repository ref inventory is not exact" >&2
        printf 'actual ref: %s\n' "${repository_refs[@]}" >&2
        exit 65
    fi
else
    if [[ "$release_ref_count" -ne 0 ]]; then
        echo "Empty Flatpak rollback repository exposes application state" >&2
        printf 'actual ref: %s\n' "${repository_refs[@]}" >&2
        exit 65
    fi
fi

ostree fsck --repo="$repo_dir"
prune_state="$(ostree prune --repo="$repo_dir" --refs-only --no-prune 2>&1)"
if ! grep -Fxq 'No unreachable objects' <<< "$prune_state"; then
    echo "Flatpak release repository contains unreachable objects" >&2
    printf '%s\n' "$prune_state" >&2
    exit 65
fi

if [[ "${#repository_refs[@]}" -gt 0 ]]; then
    listing_file="$(mktemp)"
    readonly listing_file
    trap 'rm -f "$listing_file"' EXIT
    declare -A reachable_commits=()
    for repository_ref in "${repository_refs[@]}"; do
        while IFS= read -r commit; do
            if [[ ! "$commit" =~ ^[0-9a-f]{64}$ ]]; then
                echo "Flatpak release history contains an invalid commit" >&2
                exit 65
            fi
            reachable_commits["$commit"]=1
        done < <(
            ostree log --repo="$repo_dir" "$repository_ref" \
                | awk '$1 == "commit" { print $2 }'
        )
    done
    while IFS= read -r commit; do
        ostree ls --repo="$repo_dir" --recursive "$commit" \
            >> "$listing_file"
    done < <(printf '%s\n' "${!reachable_commits[@]}" | LC_ALL=C sort)
    if [[ ! -s "$listing_file" ]]; then
        echo "Flatpak release repository history is empty" >&2
        exit 65
    fi
    if grep -Eq \
        '(^|/)(source|src|tests?)(/|$)|(^|/).*\.(c|cc|cpp|cxx|h|hh|hpp|pro|ui|qrc)$|(^|/)CMakeLists\.txt$|(^|/).*\.debug($|/)' \
        < <(awk '$1 ~ /^[-l]/ {
            $1=$2=$3=$4=""; sub(/^ +/, ""); print
          }' "$listing_file"); then
        echo "Flatpak release repository history contains source or debug payload" >&2
        exit 65
    fi
fi

echo "Verified source-free Flatpak $expected_state repository"
