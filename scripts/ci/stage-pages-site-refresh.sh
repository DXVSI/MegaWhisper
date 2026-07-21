#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $# -ne 4 ]]; then
    echo "usage: $0 SOURCE_SITE_DIR SOURCE_IMAGE_DIR BASELINE_SITE_DIR OUTPUT_SITE_DIR" >&2
    exit 64
fi

source_site_dir="$(realpath "$1")"
source_image_dir="$(realpath "$2")"
baseline_site_dir="$(realpath "$3")"
output_site_dir="$(realpath -m "$4")"
readonly source_site_dir source_image_dir baseline_site_dir output_site_dir

for command_name in cp find install mkdir realpath sha256sum sort; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        echo "required command not found: $command_name" >&2
        exit 69
    fi
done

if [[ ! -d "$source_site_dir" || -L "$source_site_dir" \
      || ! -d "$source_image_dir" || -L "$source_image_dir" \
      || ! -d "$baseline_site_dir" || -L "$baseline_site_dir" ]]; then
    echo "site refresh inputs must be regular directories" >&2
    exit 66
fi
if [[ -e "$source_site_dir/site-manifest.sha256" ]]; then
    echo "tracked site source must not contain a generated manifest" >&2
    exit 65
fi
if [[ -e "$output_site_dir" ]] \
    && [[ -n "$(find "$output_site_dir" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
    echo "site refresh output directory must be empty: $output_site_dir" >&2
    exit 73
fi

for file_name in \
    io.github.dxvsi.megawhisper.flatpakref \
    io.github.dxvsi.megawhisper.flatpakrepo; do
    if [[ ! -f "$baseline_site_dir/$file_name" \
          || -L "$baseline_site_dir/$file_name" \
          || ! -s "$baseline_site_dir/$file_name" ]]; then
        echo "signed baseline install descriptor is missing: $file_name" >&2
        exit 66
    fi
done

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly script_dir

mkdir -p "$output_site_dir"
cp -a "$source_site_dir/." "$output_site_dir/"
cp -a "$source_image_dir" "$output_site_dir/img"
for file_name in \
    io.github.dxvsi.megawhisper.flatpakref \
    io.github.dxvsi.megawhisper.flatpakrepo; do
    install -m 0644 \
        "$baseline_site_dir/$file_name" "$output_site_dir/$file_name"
done

"$script_dir/verify-pages-site.sh" "$output_site_dir" release strict
(
    cd "$output_site_dir"
    while IFS= read -r -d '' file_name; do
        sha256sum -- "$file_name"
    done < <(
        find . -type f ! -name site-manifest.sha256 \
            -printf '%P\0' | LC_ALL=C sort -z
    )
) > "$output_site_dir/site-manifest.sha256"
"$script_dir/verify-pages-site.sh" "$output_site_dir" release manifest

echo "Staged deterministic Pages site refresh"
