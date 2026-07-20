#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $# -ne 2 ]]; then
    echo "usage: $0 VERSION third-party-compliance-input|recovery-input|payload|release" >&2
    exit 64
fi

readonly version="$1"
readonly mode="$2"
if [[ ! "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
    echo "release asset version must be a stable semantic version" >&2
    exit 64
fi
IFS=. read -r version_major version_minor _ <<< "$version"
if (( 10#$version_major < 2 \
      || (10#$version_major == 2 && 10#$version_minor < 1) )); then
    echo "binary-v1 release assets require version 2.1.0 or newer" >&2
    exit 64
fi
case "$mode" in
    third-party-compliance-input|recovery-input|payload|release)
        ;;
    *)
        echo "unsupported release asset mode: $mode" >&2
        exit 64
        ;;
esac

readonly -a third_party_compliance_input_names=(
    "MegaWhisper-$version-build-provenance.json"
    "MegaWhisper-AppImage-$version.spdx.json"
    "MegaWhisper-AppImage-openSUSE-corresponding-source.tar.zst"
    "MegaWhisper-AppImage-runtime-corresponding-source.tar.zst"
    "MegaWhisper-Flatpak-$version.spdx.json"
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
    "MegaWhisper-$version-third-party-compliance.tar.zst"
    "MegaWhisper-$version-recovery.tar.zst"
    "MegaWhisper-$version-x86_64.AppImage"
    "MegaWhisper-$version-x86_64.AppImage.zsync"
    "MegaWhisper-$version-x86_64.flatpak"
    "io.github.dxvsi.megawhisper.flatpakref"
    "io.github.dxvsi.megawhisper.flatpakrepo"
    "megawhisper-release-key.asc"
)

case "$mode" in
    third-party-compliance-input)
        printf '%s\n' "${third_party_compliance_input_names[@]}" \
            | LC_ALL=C sort
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
esac
