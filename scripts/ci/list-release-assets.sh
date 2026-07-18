#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $# -ne 2 ]]; then
    echo "usage: $0 VERSION compliance-input|recovery-input|payload|release|legacy-payload|legacy-release" >&2
    exit 64
fi

readonly version="$1"
readonly mode="$2"
if [[ ! "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
    echo "release asset version must be a stable semantic version" >&2
    exit 64
fi
case "$mode" in
    compliance-input|recovery-input|payload|release)
        ;;
    legacy-payload|legacy-release)
        if [[ "$version" != 2.0.0 ]]; then
            echo "legacy release assets are valid only for v2.0.0" >&2
            exit 64
        fi
        ;;
    *)
        echo "unsupported release asset mode: $mode" >&2
        exit 64
        ;;
esac

readonly -a compliance_input_names=(
    "MegaWhisper-$version-build-provenance.json"
    "MegaWhisper-AppImage-$version.spdx.json"
    "MegaWhisper-AppImage-openSUSE-corresponding-source.tar.zst"
    "MegaWhisper-AppImage-runtime-corresponding-source.tar.zst"
    "MegaWhisper-Flatpak-$version.spdx.json"
    "MegaWhisper-Source-$version.spdx.json"
    "THIRD-PARTY-NOTICES.txt"
    "qtmultimedia-everywhere-src-6.11.1.tar.xz"
    "qtmultimedia-pipewire-hook-race.patch"
    "qtmultimedia-qtbug-147011.patch"
)

readonly -a recovery_payload_names=(
    "MegaWhisper-flatpak-repo.tar.zst"
    "MegaWhisper-flatpak-rollback-repo.tar.zst"
    "MegaWhisper-pages-site.tar.zst"
    "MegaWhisper-pages-rollback-site.tar.zst"
    "flatpak-pages-recovery.txt"
)

readonly -a recovery_input_names=(
    "${recovery_payload_names[@]}"
    "MegaWhisper-flatpak-repo.tar.zst.asc"
    "MegaWhisper-flatpak-rollback-repo.tar.zst.asc"
    "MegaWhisper-pages-site.tar.zst.asc"
    "MegaWhisper-pages-rollback-site.tar.zst.asc"
    "flatpak-pages-recovery.txt.asc"
    "megawhisper-release-key.asc"
)

readonly -a payload_names=(
    "MegaWhisper-$version-compliance.tar.zst"
    "MegaWhisper-$version-recovery.tar.zst"
    "MegaWhisper-$version-source.tar.zst"
    "MegaWhisper-$version-x86_64.AppImage"
    "MegaWhisper-$version-x86_64.AppImage.zsync"
    "MegaWhisper-$version-x86_64.flatpak"
    "io.github.dxvsi.megawhisper.flatpakref"
    "io.github.dxvsi.megawhisper.flatpakrepo"
    "megawhisper-release-key.asc"
)

readonly -a legacy_payload_names=(
    "MegaWhisper-$version-build-provenance.json"
    "MegaWhisper-$version-release-notes.md"
    "MegaWhisper-$version-source.tar.zst"
    "MegaWhisper-$version-x86_64.AppImage"
    "MegaWhisper-$version-x86_64.AppImage.sha256"
    "MegaWhisper-$version-x86_64.AppImage.zsync"
    "MegaWhisper-$version-x86_64.flatpak"
    "MegaWhisper-AppImage-$version.spdx.json"
    "MegaWhisper-AppImage-openSUSE-corresponding-source.tar.zst"
    "MegaWhisper-AppImage-runtime-corresponding-source.tar.zst"
    "MegaWhisper-Flatpak-$version.spdx.json"
    "MegaWhisper-Source-$version.spdx.json"
    "MegaWhisper-flatpak-repo.tar.zst"
    "MegaWhisper-flatpak-rollback-repo.tar.zst"
    "MegaWhisper-pages-site.tar.zst"
    "MegaWhisper-pages-rollback-site.tar.zst"
    "flatpak-pages-recovery.txt"
    "io.github.dxvsi.megawhisper.flatpakref"
    "io.github.dxvsi.megawhisper.flatpakrepo"
    "megawhisper-release-key.asc"
    "qtmultimedia-everywhere-src-6.11.1.tar.xz"
    "qtmultimedia-qtbug-147011.patch"
)

case "$mode" in
    compliance-input)
        printf '%s\n' "${compliance_input_names[@]}" | LC_ALL=C sort
        ;;
    recovery-input)
        printf '%s\n' "${recovery_input_names[@]}" | LC_ALL=C sort
        ;;
    payload)
        printf '%s\n' "${payload_names[@]}" | LC_ALL=C sort
        ;;
    release)
        {
            printf '%s\n' "${payload_names[@]}"
            printf '%s\n' SHA256SUMS SHA256SUMS.asc
        } | LC_ALL=C sort
        ;;
    legacy-payload)
        printf '%s\n' "${legacy_payload_names[@]}" | LC_ALL=C sort
        ;;
    legacy-release)
        {
            for file_name in "${legacy_payload_names[@]}"; do
                printf '%s\n' "$file_name"
                if [[ "$file_name" != megawhisper-release-key.asc ]]; then
                    printf '%s\n' "$file_name.asc"
                fi
            done
            printf '%s\n' SHA256SUMS SHA256SUMS.asc
        } | LC_ALL=C sort
        ;;
esac
