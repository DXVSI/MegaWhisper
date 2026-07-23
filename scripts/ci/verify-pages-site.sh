#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
    echo "usage: $0 SITE_DIR release|rollback [strict|manifest]" >&2
    exit 64
fi

site_dir="$(realpath "$1")"
readonly site_dir
readonly mode="$2"
readonly validation_mode="${3:-strict}"
if [[ "$mode" != release && "$mode" != rollback ]]; then
    echo "site verification mode must be release or rollback" >&2
    exit 64
fi
if [[ "$validation_mode" != strict && "$validation_mode" != manifest ]]; then
    echo "site validation mode must be strict or manifest" >&2
    exit 64
fi

for command_name in awk cmp find grep node realpath sed sha256sum sort stat xmllint; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        echo "required command not found: $command_name" >&2
        exit 69
    fi
done

readonly -a strict_required_files=(
    index.html
    robots.txt
    sitemap.xml
    assets/site.css
    assets/site.js
    assets/icon-recording.svg
    assets/icon.svg
    assets/megawhisper-social-icon-v2.png
    img/history.png
    img/main.png
    img/settings-audio.png
    img/settings-behavior.png
    img/settings-cloud.png
    img/settings-local.png
    img/settings-system.png
    img/settings-translation.png
)

readonly -a legacy_qt_widgets_screenshot_paths=(
    img/main.png
    img/history.png
    img/settings-local.png
    img/settings-cloud.png
    img/settings-behavior.png
    img/settings-audio.png
    img/settings-translation.png
    img/settings-system.png
)
readonly -a legacy_qt_widgets_screenshot_sha256=(
    a4d0d193e9d0d9b3550849d56778d80845bd4f6a598c98c20d89304a368df8d7
    09994c1148badf9ffef08b6189ff84d59795ce7a3793db250c6460a884f5bb16
    27bdc2b4fd415e84f148b63e18239c04f21aba88bc1ab0ce856be18a463659b3
    dc0eb4ba9d7909029b871806de34bb513cf8828012f4e3d22697537e03b8db8c
    7dea9007ec6ba443be6326896fb7b5db464afde6bf00cdaf401d46b2011ce699
    d7e8ddf686a6bcd08b801106102cc94d936e39cda4eaba9982d8c83059d589f7
    d6538fbf367fad2b2f6e24eea6c614c5d2bd1f3f8aee139f64593b431782d501
    31494cb44a35f1528d5a8c96496103d21e4f69556215dd2f5f21a096ef1ea8ac
)
if [[ "${#legacy_qt_widgets_screenshot_paths[@]}" \
      -ne "${#legacy_qt_widgets_screenshot_sha256[@]}" ]]; then
    echo "legacy screenshot path and hash inventories differ" >&2
    exit 70
fi

if [[ "$validation_mode" == strict ]]; then
    for file_name in "${strict_required_files[@]}"; do
        if [[ ! -f "$site_dir/$file_name" || -L "$site_dir/$file_name" \
              || ! -s "$site_dir/$file_name" ]]; then
            echo "required site file is missing or invalid: $file_name" >&2
            exit 66
        fi
    done
elif [[ ! -f "$site_dir/index.html" || -L "$site_dir/index.html" \
        || ! -s "$site_dir/index.html" ]]; then
    echo "historic site archive is missing its root index.html" >&2
    exit 66
fi

flatpak_ref="$site_dir/io.github.dxvsi.megawhisper.flatpakref"
flatpak_repo="$site_dir/io.github.dxvsi.megawhisper.flatpakrepo"
if [[ "$mode" == release ]]; then
    for install_file in "$flatpak_ref" "$flatpak_repo"; do
        if [[ ! -f "$install_file" || -L "$install_file" || ! -s "$install_file" ]]; then
            echo "release site is missing a signed Flatpak install file" >&2
            exit 66
        fi
    done
    grep -Fq '<body data-release-state="available">' "$site_dir/index.html"
elif [[ -e "$flatpak_ref" || -e "$flatpak_repo" ]]; then
    if [[ ! -f "$flatpak_ref" || -L "$flatpak_ref" || ! -s "$flatpak_ref" \
          || ! -f "$flatpak_repo" || -L "$flatpak_repo" \
          || ! -s "$flatpak_repo" ]]; then
        echo "rollback site must contain both Flatpak install files or neither" >&2
        exit 65
    fi
    grep -Fq '<body data-release-state="available">' "$site_dir/index.html"
else
    grep -Fq '<body data-release-state="unavailable">' "$site_dir/index.html"
fi

if find "$site_dir" -type l -print -quit | grep -q .; then
    echo "site must not contain symbolic links" >&2
    exit 65
fi
# Historic signed recovery archives are verified in manifest mode. They must
# remain usable as an exact rollback baseline even after the tracked site gains
# new presentation requirements. The desired site is always checked in strict
# mode before its manifest is generated, so current gallery policy belongs to
# that strict boundary.
if [[ "$mode" == release && "$validation_mode" == strict ]]; then
    readonly -a current_qt_quick_alt_text=(
        'alt="Current MegaWhisper Qt Quick home page"'
        'alt="Current MegaWhisper Qt Quick history page with local result variants and export controls"'
        'alt="Current MegaWhisper Qt Quick Transcription settings with the local model picker"'
        'alt="Current MegaWhisper Qt Quick Transcription settings for an OpenAI-compatible cloud endpoint"'
        'alt="Current MegaWhisper Qt Quick Output settings"'
        'alt="Current MegaWhisper Qt Quick Audio settings and microphone test"'
        'alt="Current MegaWhisper Qt Quick Output translation settings"'
        'alt="Current MegaWhisper Qt Quick General settings"'
    )
    for expected_alt_text in "${current_qt_quick_alt_text[@]}"; do
        if ! grep -Fq "$expected_alt_text" "$site_dir/index.html"; then
            echo "release site is missing the current Qt Quick gallery mapping: $expected_alt_text" >&2
            exit 65
        fi
    done
    for index in "${!legacy_qt_widgets_screenshot_paths[@]}"; do
        screenshot_path="${legacy_qt_widgets_screenshot_paths[$index]}"
        screenshot_file="$site_dir/$screenshot_path"
        if [[ ! -f "$screenshot_file" || -L "$screenshot_file" \
              || ! -s "$screenshot_file" ]]; then
            echo "release site screenshot is missing or invalid: $screenshot_path" >&2
            exit 66
        fi
        screenshot_sha256="$(sha256sum -- "$screenshot_file")"
        screenshot_sha256="${screenshot_sha256%% *}"
        if [[ "$screenshot_sha256" \
              == "${legacy_qt_widgets_screenshot_sha256[$index]}" ]]; then
            echo "release site contains a legacy Qt Widgets screenshot: $screenshot_path" >&2
            exit 65
        fi
    done
fi
if [[ "$validation_mode" == strict ]]; then
    if find "$site_dir" -mindepth 1 -maxdepth 1 \
        ! -name index.html \
        ! -name robots.txt \
        ! -name sitemap.xml \
        ! -name assets \
        ! -name img \
        ! -name io.github.dxvsi.megawhisper.flatpakref \
        ! -name io.github.dxvsi.megawhisper.flatpakrepo \
        ! -name site-manifest.sha256 \
        -print -quit | grep -q .; then
        echo "site contains an unexpected top-level entry" >&2
        exit 65
    fi
    if find "$site_dir/assets" -mindepth 1 -maxdepth 1 \
        ! -name icon-recording.svg \
        ! -name icon.svg \
        ! -name megawhisper-social-icon-v2.png \
        ! -name site.css \
        ! -name site.js \
        -print -quit | grep -q .; then
        echo "site assets directory contains an unexpected entry" >&2
        exit 65
    fi
    if find "$site_dir/img" -mindepth 1 -maxdepth 1 \
        ! -name history.png \
        ! -name main.png \
        ! -name settings-audio.png \
        ! -name settings-behavior.png \
        ! -name settings-cloud.png \
        ! -name settings-local.png \
        ! -name settings-system.png \
        ! -name settings-translation.png \
        -print -quit | grep -q .; then
        echo "site image directory contains an unexpected entry" >&2
        exit 65
    fi
fi

manifest_file="$site_dir/site-manifest.sha256"
if [[ "$validation_mode" == manifest && ! -s "$manifest_file" ]]; then
    echo "historic site archive is missing its signed file manifest" >&2
    exit 66
fi
if [[ -e "$manifest_file" || -L "$manifest_file" ]]; then
    if [[ ! -f "$manifest_file" || -L "$manifest_file" \
          || ! -s "$manifest_file" ]]; then
        echo "site file manifest is not a non-empty regular file" >&2
        exit 66
    fi
    declare -a manifest_files=()
    while IFS= read -r manifest_line || [[ -n "$manifest_line" ]]; do
        manifest_hash="${manifest_line%%  *}"
        manifest_path="${manifest_line#*  }"
        if [[ ! "$manifest_hash" =~ ^[0-9a-f]{64}$ \
              || "$manifest_line" != "$manifest_hash  $manifest_path" \
              || ! "$manifest_path" \
                  =~ ^[A-Za-z0-9][A-Za-z0-9._/-]*$ \
              || "$manifest_path" == *//* \
              || "$manifest_path" == ../* \
              || "$manifest_path" == */../* \
              || "$manifest_path" == */.. \
              || "$manifest_path" == site-manifest.sha256 ]]; then
            echo "site file manifest contains an unsafe entry" >&2
            exit 65
        fi
        manifest_files+=("$manifest_path")
    done < "$manifest_file"
    if [[ "${#manifest_files[@]}" -eq 0 ]]; then
        echo "site file manifest is empty" >&2
        exit 65
    fi
    manifest_file_list="$(printf '%s\n' "${manifest_files[@]}")"
    sorted_manifest_file_list="$(
        printf '%s\n' "${manifest_files[@]}" | LC_ALL=C sort
    )"
    unique_manifest_file_list="$(
        printf '%s\n' "${manifest_files[@]}" | LC_ALL=C sort -u
    )"
    actual_file_list="$(
        find "$site_dir" -type f ! -name site-manifest.sha256 \
            -printf '%P\n' | LC_ALL=C sort
    )"
    if [[ "$manifest_file_list" != "$sorted_manifest_file_list" \
          || "$sorted_manifest_file_list" != "$unique_manifest_file_list" \
          || "$unique_manifest_file_list" != "$actual_file_list" ]]; then
        echo "site file manifest inventory is not exact and deterministic" >&2
        exit 65
    fi
    (
        cd "$site_dir"
        sha256sum --check --strict --quiet site-manifest.sha256
    )
fi

readonly maximum_site_bytes=$((5 * 1024 * 1024))
site_bytes="$(find "$site_dir" -type f -printf '%s\n' \
    | awk '{ total += $1 } END { print total + 0 }')"
if [[ ! "$site_bytes" =~ ^[0-9]+$ || "$site_bytes" -gt "$maximum_site_bytes" ]]; then
    echo "site payload exceeds the 5 MiB budget: $site_bytes bytes" >&2
    exit 65
fi

readonly index_file="$site_dir/index.html"
if [[ "$validation_mode" == strict ]]; then
    grep -Fq '<!doctype html>' "$index_file"
    grep -Fq '<html lang="en">' "$index_file"
    grep -Fq 'Content-Security-Policy' "$index_file"
    grep -Fq 'https://dxvsi.github.io/MegaWhisper/' "$index_file"
    grep -Fq 'href="https://github.com/DXVSI"' "$index_file"
    grep -Fq '>DXVSI<' "$index_file"
    grep -Fq 'Proprietary license' "$index_file"
    grep -Fq 'href="https://github.com/DXVSI/MegaWhisper/blob/main/LICENSE"' \
        "$index_file"
    grep -Fq \
        'href="https://github.com/DXVSI/MegaWhisper/blob/main/THIRD_PARTY_NOTICES.md"' \
        "$index_file"
    grep -Fq 'data-language="en"' "$index_file"
    grep -Fq 'data-language="ru"' "$index_file"
    grep -Fq 'data-ru=' "$index_file"
    grep -Fq 'assets/site.css' "$index_file"
    grep -Fq 'assets/site.js' "$index_file"
    grep -Fq \
        '<meta property="og:image" content="https://dxvsi.github.io/MegaWhisper/assets/megawhisper-social-icon-v2.png">' \
        "$index_file"
    grep -Fq '<meta property="og:image:type" content="image/png">' "$index_file"
    grep -Fq '<meta property="og:image:width" content="512">' "$index_file"
    grep -Fq '<meta property="og:image:height" content="512">' "$index_file"
    grep -Fq '<meta name="twitter:card" content="summary">' "$index_file"
    grep -Fq \
        '<meta name="twitter:image" content="https://dxvsi.github.io/MegaWhisper/assets/megawhisper-social-icon-v2.png">' \
        "$index_file"
    grep -Fq \
        'https://dxvsi.github.io/MegaWhisper/io.github.dxvsi.megawhisper.flatpakref' \
        "$index_file"
    if grep -Eiq 'GPL-3\.0|open[- ]source|source snapshots?' "$index_file"; then
        echo "site contains obsolete application source or GPL wording" >&2
        exit 65
    fi

    if grep -REn \
        '(src|href)="(https?:)?//[^"]+\.(css|js)([?#][^"]*)?"' \
        "$index_file"; then
        echo "site must not load external CSS or JavaScript" >&2
        exit 65
    fi
    if grep -REn \
        'https?://(fonts\.googleapis\.com|fonts\.gstatic\.com|cdn\.jsdelivr\.net|unpkg\.com)' \
        "$site_dir"; then
        echo "site contains a forbidden external runtime dependency" >&2
        exit 65
    fi
    if grep -REn \
        '(google-analytics|googletagmanager|segment\.com|plausible\.io|posthog|mixpanel|hotjar)' \
        "$site_dir"; then
        echo "site contains analytics or tracking code" >&2
        exit 65
    fi
    if grep -REn \
        '(serviceWorker|service-worker|navigator\.serviceWorker)' \
        "$site_dir"; then
        echo "site must not register a service worker" >&2
        exit 65
    fi

    while IFS= read -r asset_path; do
        case "$asset_path" in
            http://*|https://*|data:*|\#*|'')
                continue
                ;;
        esac
        asset_path="${asset_path%%\?*}"
        asset_path="${asset_path%%\#*}"
        if [[ ! -f "$site_dir/$asset_path" || -L "$site_dir/$asset_path" ]]; then
            echo "HTML references a missing local asset: $asset_path" >&2
            exit 65
        fi
    done < <(
        sed -nE 's/.*(src|href)="([^"]+)".*/\2/p' "$index_file" \
            | LC_ALL=C sort -u
    )

    node --check "$site_dir/assets/site.js"
    node - "$site_dir/assets/megawhisper-social-icon-v2.png" <<'NODE'
const fs = require("node:fs");
const image = fs.readFileSync(process.argv[2]);
const valid = image.length >= 24
  && image.subarray(0, 8).toString("hex") === "89504e470d0a1a0a"
  && image.subarray(12, 16).toString("ascii") === "IHDR"
  && image.readUInt32BE(16) === 512
  && image.readUInt32BE(20) === 512;
if (!valid) {
  console.error("social preview image must be a 512x512 PNG");
  process.exit(65);
}
NODE
    xmllint --noout "$site_dir/sitemap.xml"
    xmllint --noout "$site_dir/assets/icon.svg"
    xmllint --noout "$site_dir/assets/icon-recording.svg"
fi

if [[ -f "$flatpak_ref" ]]; then
    grep -Fq '[Flatpak Ref]' "$flatpak_ref"
    grep -Fq 'Name=io.github.dxvsi.megawhisper' "$flatpak_ref"
    grep -Eq '^Url=https://' "$flatpak_ref"
fi
if [[ -f "$flatpak_repo" ]]; then
    grep -Fq '[Flatpak Repo]' "$flatpak_repo"
    grep -Eq '^Url=https://' "$flatpak_repo"
fi

echo "Pages site verified: mode=$mode validation=$validation_mode bytes=$site_bytes"
