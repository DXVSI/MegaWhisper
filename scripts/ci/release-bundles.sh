#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $# -ne 5 ]]; then
    echo "usage: $0 extract compliance|recovery VERSION INPUT_ARCHIVE OUTPUT_DIR" >&2
    exit 64
fi

readonly operation="$1"
readonly bundle_kind="$2"
readonly version="$3"
input_archive="$(realpath "$4")"
output_dir="$(realpath -m "$5")"
readonly input_archive output_dir
if [[ "$operation" != extract ]]; then
    echo "the public verifier supports only bundle extraction" >&2
    exit 64
fi
if [[ "$bundle_kind" != compliance && "$bundle_kind" != recovery ]]; then
    echo "bundle kind must be compliance or recovery" >&2
    exit 64
fi
if [[ ! "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
    echo "bundle version must be a stable semantic version" >&2
    exit 64
fi
for command_name in awk cmp diff find head install mkdir mktemp realpath rm \
    sha256sum sort stat tar uniq wc zstd; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        echo "required command not found: $command_name" >&2
        exit 69
    fi
done
if [[ ! -f "$input_archive" || -L "$input_archive" \
      || ! -s "$input_archive" ]]; then
    echo "bundle archive is missing or unsafe: $input_archive" >&2
    exit 66
fi
if [[ -e "$output_dir" ]] \
    && [[ -n "$(find "$output_dir" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
    echo "bundle output directory must be empty: $output_dir" >&2
    exit 73
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly script_dir
readonly list_mode="$bundle_kind-input"
mapfile -t payload_names < <(
    "$script_dir/list-release-assets.sh" "$version" "$list_mode"
)
if [[ "${#payload_names[@]}" -eq 0 ]]; then
    echo "bundle payload inventory is empty" >&2
    exit 65
fi
readonly bundle_root="MegaWhisper-$version-$bundle_kind"
readonly manifest_name="BUNDLE-MANIFEST.txt"
readonly maximum_archive_entries=64
readonly maximum_unpacked_size=2000000000
work_dir="$(mktemp -d)"
readonly work_dir
cleanup() {
    rm -rf "$work_dir"
}
trap cleanup EXIT

bundle_payload_names() {
    printf '%s\n' "${payload_names[@]}"
    if [[ "$bundle_kind" == compliance ]]; then
        printf '%s\n' COMPLIANCE.txt
    fi
}

archive_content_names() {
    bundle_payload_names
    printf '%s\n' "$manifest_name"
}

validate_metadata() {
    local root_dir="$1"
    local metadata_file expected_format
    if [[ "$bundle_kind" == compliance ]]; then
        metadata_file="$root_dir/COMPLIANCE.txt"
        expected_format=1
    else
        metadata_file="$root_dir/flatpak-pages-recovery.txt"
        expected_format=4
    fi
    declare -A metadata=()
    while IFS='=' read -r key value; do
        if [[ -z "$key" || -z "$value" \
              || -n "${metadata[$key]+present}" ]]; then
            echo "invalid or duplicate $bundle_kind metadata field: $key" >&2
            exit 65
        fi
        metadata[$key]="$value"
    done < "$metadata_file"
    if [[ "${metadata[format]-}" != "$expected_format" \
          || "${metadata[asset_schema]-}" != bundle-v1 \
          || "${metadata[version]-}" != "$version" ]]; then
        echo "$bundle_kind metadata does not identify bundle-v1 $version" >&2
        exit 65
    fi
    if [[ "$bundle_kind" == compliance ]]; then
        declare -A expected_metadata=(
            [format]=1
            [asset_schema]=bundle-v1
            [version]="$version"
            [appimage_binary]="MegaWhisper-$version-x86_64.AppImage"
            [appimage_sbom]="MegaWhisper-AppImage-$version.spdx.json"
            [flatpak_binary]="MegaWhisper-$version-x86_64.flatpak"
            [flatpak_sbom]="MegaWhisper-Flatpak-$version.spdx.json"
            [source_archive]="MegaWhisper-$version-source.tar.zst"
            [source_sbom]="MegaWhisper-Source-$version.spdx.json"
            [build_provenance]="MegaWhisper-$version-build-provenance.json"
            [third_party_notices]="THIRD-PARTY-NOTICES.txt"
            [appimage_opensuse_source]="MegaWhisper-AppImage-openSUSE-corresponding-source.tar.zst"
            [appimage_runtime_source]="MegaWhisper-AppImage-runtime-corresponding-source.tar.zst"
            [qtmultimedia_source]="qtmultimedia-everywhere-src-6.11.1.tar.xz"
            [qtmultimedia_shutdown_patch]="qtmultimedia-qtbug-147011.patch"
            [qtmultimedia_hook_race_patch]="qtmultimedia-pipewire-hook-race.patch"
        )
        if [[ "${#metadata[@]}" -ne "${#expected_metadata[@]}" ]]; then
            echo "compliance metadata field inventory is not exact" >&2
            exit 65
        fi
        local metadata_key
        for metadata_key in "${!expected_metadata[@]}"; do
            if [[ "${metadata[$metadata_key]-}" \
                  != "${expected_metadata[$metadata_key]}" ]]; then
                echo "compliance metadata mismatch: $metadata_key" >&2
                exit 65
            fi
        done
    fi
}

validate_bundle_manifest() {
    local root_dir="$1"
    local manifest_file="$root_dir/$manifest_name"
    local manifest_names expected_manifest_names
    if [[ "$(head -n 1 "$manifest_file")" != $'sha256\tsize\tpath' ]]; then
        echo "$bundle_kind bundle manifest header is invalid" >&2
        exit 65
    fi
    manifest_names="$(awk -F '\t' '
        NR == 1 { next }
        NF != 3 || $1 !~ /^[0-9a-f]{64}$/ || $2 !~ /^[0-9]+$/ {
            exit 65
        }
        $3 == "" || $3 ~ /\// || $3 ~ /^\./ { exit 65 }
        { print $3 }
    ' "$manifest_file" | LC_ALL=C sort)" || {
        echo "$bundle_kind bundle manifest contains an invalid record" >&2
        exit 65
    }
    expected_manifest_names="$(bundle_payload_names | LC_ALL=C sort)"
    if [[ "$manifest_names" != "$expected_manifest_names" ]]; then
        echo "$bundle_kind bundle manifest inventory is not exact" >&2
        exit 65
    fi
    while IFS=$'\t' read -r expected_sha256 expected_size file_name; do
        if [[ "$expected_sha256" == sha256 \
              && "$expected_size" == size \
              && "$file_name" == path ]]; then
            continue
        fi
        actual_size="$(stat -c '%s' "$root_dir/$file_name")"
        actual_sha256="$(sha256sum "$root_dir/$file_name" | awk '{print $1}')"
        if [[ "$actual_size" != "$expected_size" \
              || "$actual_sha256" != "$expected_sha256" ]]; then
            echo "$bundle_kind bundle manifest mismatch for $file_name" >&2
            exit 65
        fi
    done < "$manifest_file"
}

listing_file="$work_dir/archive-listing.txt"
verbose_listing_file="$work_dir/archive-verbose-listing.txt"
tar --zstd --list --file "$input_archive" > "$listing_file"
tar --zstd --list --verbose --numeric-owner --full-time \
    --file "$input_archive" > "$verbose_listing_file"
entry_count="$(wc -l < "$listing_file")"
if [[ ! "$entry_count" =~ ^[0-9]+$ || "$entry_count" -eq 0 \
      || "$entry_count" -gt "$maximum_archive_entries" ]]; then
    echo "bundle archive entry count is invalid" >&2
    exit 65
fi
if [[ -n "$(LC_ALL=C sort "$listing_file" | uniq -d)" ]]; then
    echo "bundle archive contains duplicate entries" >&2
    exit 65
fi
if awk 'substr($0, 1, 1) != "-" && substr($0, 1, 1) != "d" { bad=1 }
    END { exit !bad }' "$verbose_listing_file"; then
    echo "bundle archive contains links or special files" >&2
    exit 65
fi
declared_size="$(awk '
    substr($0, 1, 1) == "-" {
        if ($3 !~ /^[0-9]+$/) exit 65
        total += $3
    }
    END { printf "%.0f\n", total }
' "$verbose_listing_file")" || {
    echo "bundle archive has invalid declared file sizes" >&2
    exit 65
}
if [[ ! "$declared_size" =~ ^[0-9]+$ \
      || "$declared_size" -gt "$maximum_unpacked_size" ]]; then
    echo "bundle declared size is invalid or exceeds the limit" >&2
    exit 65
fi
expected_listing="$({
    printf '%s/\n' "$bundle_root"
    while IFS= read -r file_name; do
        printf '%s/%s\n' "$bundle_root" "$file_name"
    done < <({ archive_content_names; printf '%s\n' SHA256SUMS; } \
        | LC_ALL=C sort)
} | LC_ALL=C sort)"
actual_listing="$(LC_ALL=C sort "$listing_file")"
if [[ "$actual_listing" != "$expected_listing" ]]; then
    echo "bundle archive path inventory is not exact" >&2
    diff -u <(printf '%s\n' "$expected_listing") \
        <(printf '%s\n' "$actual_listing") >&2 || true
    exit 65
fi

extraction_dir="$work_dir/extracted"
mkdir -p "$extraction_dir"
tar --zstd --extract --file "$input_archive" \
    --directory "$extraction_dir" --no-same-owner --no-same-permissions
extracted_root="$extraction_dir/$bundle_root"
if [[ ! -d "$extracted_root" || -L "$extracted_root" \
      || -n "$(find "$extracted_root" -mindepth 1 -type l -print -quit)" ]]; then
    echo "bundle extracted root is missing or unsafe" >&2
    exit 65
fi
actual_names="$(find "$extracted_root" -mindepth 1 -maxdepth 1 \
    -type f -printf '%f\n' | LC_ALL=C sort)"
expected_names="$({ archive_content_names; printf '%s\n' SHA256SUMS; } \
    | LC_ALL=C sort)"
if [[ "$actual_names" != "$expected_names" \
      || -n "$(find "$extracted_root" -mindepth 1 -maxdepth 1 \
          ! -type f -print -quit)" ]]; then
    echo "extracted $bundle_kind inventory is not exact" >&2
    exit 65
fi
unpacked_size="$(find "$extracted_root" -maxdepth 1 -type f -printf '%s\n' \
    | awk '{ total += $1 } END { printf "%.0f\n", total }')"
if [[ ! "$unpacked_size" =~ ^[0-9]+$ \
      || "$unpacked_size" -gt "$maximum_unpacked_size" ]]; then
    echo "bundle unpacked size is invalid or exceeds the limit" >&2
    exit 65
fi
checksum_names="$(awk '
    NF != 2 || $1 !~ /^[0-9a-f]{64}$/ || substr($2, 1, 1) != "*" {
        exit 65
    }
    {
        name=substr($2, 2)
        if (name == "" || name ~ /\// || name ~ /^\./) exit 65
        print name
    }
' "$extracted_root/SHA256SUMS" | LC_ALL=C sort)" || {
    echo "bundle SHA256SUMS has an invalid entry" >&2
    exit 65
}
expected_checksum_names="$(archive_content_names | LC_ALL=C sort)"
if [[ "$checksum_names" != "$expected_checksum_names" ]]; then
    echo "bundle checksum inventory is not exact" >&2
    exit 65
fi
(
    cd "$extracted_root"
    sha256sum --check --strict SHA256SUMS
)
validate_bundle_manifest "$extracted_root"
validate_metadata "$extracted_root"

mkdir -p "$output_dir"
while IFS= read -r file_name; do
    install -m 0644 "$extracted_root/$file_name" "$output_dir/$file_name"
done < <(bundle_payload_names)
echo "Extracted verified $bundle_kind bundle for $version"
