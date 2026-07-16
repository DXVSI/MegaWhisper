#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $# -ne 2 ]]; then
    echo "usage: $0 VERSION payload|release" >&2
    exit 64
fi

readonly version="$1"
readonly mode="$2"
if [[ ! "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
    echo "release asset version must be a stable semantic version" >&2
    exit 64
fi
if [[ "$mode" != payload && "$mode" != release ]]; then
    echo "release asset mode must be payload or release" >&2
    exit 64
fi

readonly -a payload_names=(
    "MegaWhisper-$version-x86_64.AppImage"
    "MegaWhisper-$version-x86_64.AppImage.sha256"
    "MegaWhisper-$version-x86_64.AppImage.zsync"
    "MegaWhisper-AppImage-openSUSE-corresponding-source.tar.zst"
    "MegaWhisper-AppImage-runtime-corresponding-source.tar.zst"
    "MegaWhisper-$version-source.tar.zst"
    "MegaWhisper-Source-$version.spdx.json"
    "qtmultimedia-everywhere-src-6.11.1.tar.xz"
    "qtmultimedia-qtbug-147011.patch"
    "MegaWhisper-$version-release-notes.md"
    "MegaWhisper-AppImage-$version.spdx.json"
    "MegaWhisper-Flatpak-$version.spdx.json"
    "MegaWhisper-$version-x86_64.flatpak"
    "io.github.dxvsi.megawhisper.flatpakrepo"
    "io.github.dxvsi.megawhisper.flatpakref"
    "MegaWhisper-flatpak-repo.tar.zst"
    "MegaWhisper-flatpak-rollback-repo.tar.zst"
    "MegaWhisper-pages-site.tar.zst"
    "MegaWhisper-pages-rollback-site.tar.zst"
    "flatpak-pages-recovery.txt"
    "MegaWhisper-$version-build-provenance.json"
    "megawhisper-release-key.asc"
)

if [[ "$mode" == payload ]]; then
    printf '%s\n' "${payload_names[@]}" | LC_ALL=C sort
    exit 0
fi

{
    for file_name in "${payload_names[@]}"; do
        printf '%s\n' "$file_name"
        if [[ "$file_name" != megawhisper-release-key.asc ]]; then
            printf '%s\n' "$file_name.asc"
        fi
    done
    printf '%s\n' SHA256SUMS SHA256SUMS.asc
} | LC_ALL=C sort
