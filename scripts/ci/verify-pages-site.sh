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
    img/history.png
    img/main.png
    img/settings-audio.png
    img/settings-behavior.png
    img/settings-cloud.png
    img/settings-local.png
    img/settings-system.png
    img/settings-translation.png
)

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
