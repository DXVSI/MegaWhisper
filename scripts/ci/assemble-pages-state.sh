#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $# -ne 5 ]]; then
    echo "usage: $0 SITE_DIR REPO_DIR OUTPUT_DIR EXPECTED_COMMIT|none release|rollback" >&2
    exit 64
fi

site_dir="$(realpath "$1")"
repo_dir="$(realpath "$2")"
output_dir="$(realpath -m "$3")"
readonly site_dir repo_dir output_dir
readonly expected_commit="$4"
readonly mode="$5"
if [[ ! "$expected_commit" =~ ^(none|[0-9a-f]{64})$ \
      || ( "$mode" != release && "$mode" != rollback ) ]]; then
    echo "expected commit or Pages state mode is invalid" >&2
    exit 64
fi

for command_name in comm cp du find ostree realpath sort; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        echo "required command not found: $command_name" >&2
        exit 69
    fi
done

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly script_dir
site_validation_mode=strict
if [[ -s "$site_dir/site-manifest.sha256" ]]; then
    site_validation_mode=manifest
fi
"$script_dir/verify-pages-site.sh" \
    "$site_dir" "$mode" "$site_validation_mode"
ostree fsck --repo="$repo_dir"

readonly app_ref="app/io.github.dxvsi.megawhisper/x86_64/stable"
actual_commit="$(ostree rev-parse --repo="$repo_dir" "$app_ref" 2>/dev/null || true)"
if [[ "$expected_commit" == none ]]; then
    if [[ -n "$actual_commit" ]]; then
        echo "empty rollback repository unexpectedly exposes the stable app ref" >&2
        exit 65
    fi
elif [[ "$actual_commit" != "$expected_commit" ]]; then
    echo "repository commit does not match the requested Pages state" >&2
    exit 65
fi

if [[ -e "$output_dir" ]] \
    && [[ -n "$(find "$output_dir" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
    echo "Pages output directory must be empty: $output_dir" >&2
    exit 73
fi

work_dir="$(mktemp -d)"
readonly work_dir
cleanup() {
    rm -rf "$work_dir"
}
trap cleanup EXIT
find "$site_dir" -mindepth 1 -printf '%P\n' | LC_ALL=C sort -u \
    > "$work_dir/site-entries"
find "$repo_dir" -mindepth 1 -printf '%P\n' | LC_ALL=C sort -u \
    > "$work_dir/repo-entries"
if comm -12 "$work_dir/site-entries" "$work_dir/repo-entries" \
    | grep -q .; then
    echo "site and OSTree repository paths overlap" >&2
    comm -12 "$work_dir/site-entries" "$work_dir/repo-entries" >&2
    exit 65
fi

mkdir -p "$output_dir"
cp -a "$site_dir/." "$output_dir/"
cp -a "$repo_dir/." "$output_dir/"
if [[ ! -f "$output_dir/index.html" || ! -f "$output_dir/config" \
      || ! -f "$output_dir/summary" ]]; then
    echo "assembled Pages state is incomplete" >&2
    exit 65
fi
if [[ "$(find "$output_dir" -name config -type f | wc -l)" -ne 1 ]]; then
    echo "assembled Pages state must contain exactly one OSTree config" >&2
    exit 65
fi

readonly maximum_pages_bytes=$((900 * 1024 * 1024))
pages_bytes="$(du -sb "$output_dir" | awk '{print $1}')"
if [[ ! "$pages_bytes" =~ ^[0-9]+$ \
      || "$pages_bytes" -gt "$maximum_pages_bytes" ]]; then
    echo "assembled Pages state exceeds the 900 MiB safety limit: $pages_bytes bytes" >&2
    exit 65
fi

echo "Assembled Pages state: mode=$mode commit=$expected_commit bytes=$pages_bytes"
