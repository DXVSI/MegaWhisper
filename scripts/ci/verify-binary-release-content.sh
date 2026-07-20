#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $# -ne 4 ]]; then
    echo "usage: $0 VERSION ARTIFACT_DIR APPIMAGE_ROOT FLATPAK_ROOT" >&2
    exit 64
fi

readonly version="$1"
artifact_dir="$(realpath "$2")"
appimage_root="$(realpath "$3")"
flatpak_root="$(realpath "$4")"
readonly artifact_dir appimage_root flatpak_root
if [[ ! "$version" \
      =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
    echo "binary release verification version is invalid" >&2
    exit 64
fi
IFS=. read -r version_major version_minor _ <<< "$version"
if (( 10#$version_major < 2 \
      || (10#$version_major == 2 && 10#$version_minor < 1) )); then
    echo "binary release verification requires version 2.1.0 or newer" >&2
    exit 64
fi
for command_name in find grep mktemp readelf realpath rm strings; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        echo "required command not found: $command_name" >&2
        exit 69
    fi
done

work_dir="$(mktemp -d)"
readonly work_dir
trap 'rm -rf "$work_dir"' EXIT
for required_dir in "$artifact_dir" "$appimage_root" "$flatpak_root"; do
    if [[ ! -d "$required_dir" || -L "$required_dir" ]]; then
        echo "binary release verification directory is missing: $required_dir" >&2
        exit 66
    fi
done

for forbidden_path in \
    "$artifact_dir/MegaWhisper-$version-source.tar.zst" \
    "$artifact_dir/MegaWhisper-Source-$version.spdx.json" \
    "$artifact_dir/SOURCE-GRAPH.txt"; do
    if [[ -e "$forbidden_path" || -L "$forbidden_path" ]]; then
        echo "application source release artifact is forbidden: $forbidden_path" >&2
        exit 65
    fi
done

for package_root in "$appimage_root" "$flatpak_root"; do
    if find "$package_root" -type d \
        \( -name src -o -name tests \) -print -quit | grep -q .; then
        echo "binary package contains an application source directory: $package_root" >&2
        exit 65
    fi
    if find "$package_root" -type f \
        \( -name '*.c' -o -name '*.cpp' -o -name '*.cc' -o -name '*.cxx' \
           -o -name '*.h' -o -name '*.hh' -o -name '*.hpp' \
           -o -name '*.pro' -o -name '*.ui' -o -name '*.qrc' \
           -o -name CMakeLists.txt -o -name 'SOURCE-GRAPH.txt' \) \
        -print -quit | grep -q .; then
        echo "binary package contains application source-shaped files: $package_root" >&2
        exit 65
    fi
done

assert_regular_nonempty_file() {
    local file_path="$1"
    if [[ ! -f "$file_path" || -L "$file_path" || ! -s "$file_path" ]]; then
        echo "required packaged license file is missing: $file_path" >&2
        exit 65
    fi
}

readonly appimage_license_root="$appimage_root/usr/share/licenses/megawhisper"
readonly flatpak_license_root="$flatpak_root/files/share/licenses/megawhisper"
for license_root in "$appimage_license_root" "$flatpak_license_root"; do
    assert_regular_nonempty_file "$license_root/LICENSE"
    assert_regular_nonempty_file "$license_root/THIRD_PARTY_NOTICES.md"
    assert_regular_nonempty_file "$license_root/whisper.cpp/LICENSE"
    grep -Fq 'MegaWhisper Proprietary Software License' \
        "$license_root/LICENSE"
    grep -Fq 'All rights reserved.' "$license_root/LICENSE"
    grep -Fq 'MegaWhisper third-party notices' \
        "$license_root/THIRD_PARTY_NOTICES.md"
    grep -Fq 'MIT License' "$license_root/whisper.cpp/LICENSE"
    grep -Fq 'The ggml authors' "$license_root/whisper.cpp/LICENSE"
done

readonly flatpak_qt_lgpl="$flatpak_root/files/share/licenses/qtmultimedia/LGPL-3.0-only.txt"
assert_regular_nonempty_file "$flatpak_qt_lgpl"
grep -Fq 'GNU LESSER GENERAL PUBLIC LICENSE' "$flatpak_qt_lgpl"

mapfile -t appimage_binaries < <(
    find "$appimage_root" -type f -path '*/bin/megawhisper' -print
)
mapfile -t flatpak_binaries < <(
    find "$flatpak_root" -type f -path '*/bin/megawhisper' -print
)
if [[ "${#appimage_binaries[@]}" -ne 1 \
      || "${#flatpak_binaries[@]}" -ne 1 ]]; then
    echo "binary package must contain exactly one MegaWhisper executable" >&2
    exit 65
fi
executable_index=0
for executable in "${appimage_binaries[0]}" "${flatpak_binaries[0]}"; do
    executable_index=$((executable_index + 1))
    section_listing="$work_dir/executable-$executable_index.sections"
    string_listing="$work_dir/executable-$executable_index.strings"
    if ! readelf --wide --sections "$executable" > "$section_listing" \
        || ! strings --all "$executable" > "$string_listing"; then
        echo "failed to inspect release executable: $executable" >&2
        exit 65
    fi
    if grep -Eq '[[:space:]]\.(z?debug_|gnu_debuglink)' "$section_listing"; then
        echo "release executable contains debug sections: $executable" >&2
        exit 65
    fi
    if grep -Eq '/home/(runner/work/[^/]+/[^/]+|dx/project/whisper)|/__w/[^/]+/[^/]+' \
        "$string_listing"; then
        echo "release executable contains a private checkout path: $executable" >&2
        exit 65
    fi
done

while IFS= read -r metadata_file; do
    if grep -Eaq \
        'privateSourceCommit|publicSourceCommit|source_run_id=|source_sha=|public_source_sha=|SOURCE-GRAPH\.txt|/home/(runner|dx)/|/__w/[^/]+/[^/]+|(^|/)sbom-input/(appimage|flatpak)(/|$)' \
        "$metadata_file"; then
        echo "release metadata exposes an application source identity: $metadata_file" >&2
        exit 65
    fi
done < <(find "$artifact_dir" -maxdepth 1 -type f \
    \( -name '*.json' -o -name '*.txt' -o -name '*.md' \) -print)

echo "Verified source-free binary package contents for $version"
