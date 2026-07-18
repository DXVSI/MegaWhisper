#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $# -ne 2 ]]; then
    echo "usage: $0 ARCHIVE OUTPUT_DIR" >&2
    exit 64
fi

archive="$(realpath "$1")"
output_dir="$(realpath -m "$2")"
readonly archive output_dir
readonly maximum_archive_entries=200000
readonly maximum_unpacked_size=2000000000

for command_name in awk find mkdir mktemp realpath rm sort tar uniq wc; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        echo "required command not found: $command_name" >&2
        exit 69
    fi
done
if [[ ! -f "$archive" || -L "$archive" || ! -s "$archive" ]]; then
    echo "recovery archive is missing or unsafe: $archive" >&2
    exit 66
fi
if [[ -e "$output_dir" ]] \
    && [[ -n "$(find "$output_dir" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
    echo "recovery archive destination must be empty: $output_dir" >&2
    exit 73
fi

work_dir="$(mktemp -d)"
readonly work_dir
cleanup() {
    rm -rf "$work_dir"
}
trap cleanup EXIT

listing_file="$work_dir/listing.txt"
verbose_listing_file="$work_dir/verbose-listing.txt"
tar --zstd --list --file "$archive" > "$listing_file"
tar --zstd --list --verbose --numeric-owner --full-time \
    --file "$archive" > "$verbose_listing_file"

entry_count="$(wc -l < "$listing_file")"
if [[ ! "$entry_count" =~ ^[0-9]+$ \
      || "$entry_count" -eq 0 \
      || "$entry_count" -gt "$maximum_archive_entries" ]]; then
    echo "recovery archive entry count is invalid" >&2
    exit 65
fi
if [[ -n "$(LC_ALL=C sort "$listing_file" | uniq -d)" ]]; then
    echo "recovery archive contains duplicate paths" >&2
    exit 65
fi
if ! awk '
    function unsafe(path, count, parts, item_index, relative) {
        if (path == "./")
            return 0
        if (path !~ /^\.\//)
            return 1
        relative = substr(path, 3)
        sub(/\/$/, "", relative)
        if (relative == "" || relative ~ /\/\//)
            return 1
        count = split(relative, parts, "/")
        for (item_index = 1; item_index <= count; item_index++) {
            if (parts[item_index] == "" || parts[item_index] == "." \
                || parts[item_index] == "..")
                return 1
        }
        return 0
    }
    unsafe($0) { exit 65 }
' "$listing_file"; then
    echo "recovery archive contains a non-canonical or unsafe path" >&2
    exit 65
fi
if awk 'substr($0, 1, 1) != "-" && substr($0, 1, 1) != "d" { bad=1 }
    END { exit !bad }' "$verbose_listing_file"; then
    echo "recovery archive contains links or special files" >&2
    exit 65
fi
declared_size="$(awk '
    substr($0, 1, 1) == "-" {
        if ($3 !~ /^[0-9]+$/) exit 65
        total += $3
    }
    END { printf "%.0f\n", total }
' "$verbose_listing_file")" || {
    echo "recovery archive declares invalid file sizes" >&2
    exit 65
}
if [[ ! "$declared_size" =~ ^[0-9]+$ \
      || "$declared_size" -gt "$maximum_unpacked_size" ]]; then
    echo "recovery archive exceeds the unpacked size limit" >&2
    exit 65
fi

mkdir -p "$output_dir"
tar --zstd --extract --file "$archive" \
    --directory "$output_dir" --no-same-owner --no-same-permissions
if [[ -n "$(find "$output_dir" -mindepth 1 \
      ! -type d ! -type f -print -quit)" ]]; then
    echo "recovery archive extracted a link or special file" >&2
    exit 65
fi
unpacked_size="$(find "$output_dir" -type f -printf '%s\n' \
    | awk '{ total += $1 } END { printf "%.0f\n", total }')"
extracted_entries="$(find "$output_dir" -mindepth 1 -printf '.\n' | wc -l)"
if [[ ! "$unpacked_size" =~ ^[0-9]+$ \
      || "$unpacked_size" -gt "$maximum_unpacked_size" \
      || ! "$extracted_entries" =~ ^[0-9]+$ \
      || "$extracted_entries" -gt "$maximum_archive_entries" ]]; then
    echo "extracted recovery archive exceeds a safety limit" >&2
    exit 65
fi
