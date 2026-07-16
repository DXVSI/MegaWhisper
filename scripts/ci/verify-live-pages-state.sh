#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $# -ne 7 ]]; then
    echo "usage: $0 BASE_URL EXPECTED_PAGES_DIR EXPECTED_SITE_DIR EXPECTED_FINGERPRINT EXPECTED_COMMIT|none RUN_TOKEN release|rollback" >&2
    exit 64
fi

readonly base_url="${1%/}"
expected_pages_dir="$(realpath "$2")"
expected_site_dir="$(realpath "$3")"
readonly expected_pages_dir expected_site_dir
readonly expected_fingerprint="${4^^}"
readonly expected_commit="$5"
readonly run_token="$6"
readonly mode="$7"
if [[ ! "$base_url" =~ ^https://[A-Za-z0-9.-]+(:[0-9]+)?(/[A-Za-z0-9._~!$&()*+,;=:@%/-]*)?$ \
      || ! "$expected_fingerprint" =~ ^([0-9A-F]{40}|[0-9A-F]{64})$ \
      || ! "$expected_commit" =~ ^(none|[0-9a-f]{64})$ \
      || ! "$run_token" =~ ^[A-Za-z0-9._-]+$ \
      || ( "$mode" != release && "$mode" != rollback ) ]]; then
    echo "live Pages verification arguments are invalid" >&2
    exit 64
fi

for command_name in cmp curl find mktemp realpath sort; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        echo "required command not found: $command_name" >&2
        exit 69
    fi
done

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly script_dir
site_validation_mode=strict
if [[ -s "$expected_site_dir/site-manifest.sha256" ]]; then
    site_validation_mode=manifest
fi
"$script_dir/verify-pages-site.sh" \
    "$expected_site_dir" "$mode" "$site_validation_mode"

work_dir="$(mktemp -d)"
readonly work_dir
cleanup() {
    rm -rf "$work_dir"
}
trap cleanup EXIT

declare -a site_files=()
if [[ -f "$expected_site_dir/site-manifest.sha256" ]]; then
    site_files+=(site-manifest.sha256)
    while IFS= read -r file_name; do
        site_files+=("$file_name")
    done < <(
        sed -nE 's/^[0-9a-f]{64}  (.+)$/\1/p' \
            "$expected_site_dir/site-manifest.sha256"
    )
else
    site_files=(
        index.html
        robots.txt
        sitemap.xml
    )
    while IFS= read -r file_name; do
        site_files+=("$file_name")
    done < <(
        {
            find "$expected_site_dir/assets" -type f -printf '%P\n' \
                | sed -e 's#^#assets/#'
            find "$expected_site_dir/img" -type f -printf '%P\n' \
                | sed -e 's#^#img/#'
        } | LC_ALL=C sort
    )
    for install_file in \
        io.github.dxvsi.megawhisper.flatpakref \
        io.github.dxvsi.megawhisper.flatpakrepo; do
        if [[ -f "$expected_site_dir/$install_file" ]]; then
            site_files+=("$install_file")
        fi
    done
fi

origin="${base_url#https://}"
origin="${origin%%/*}"
counter=0
for file_name in "${site_files[@]}"; do
    if [[ ! -f "$expected_pages_dir/$file_name" ]] \
        || ! cmp --silent \
            "$expected_site_dir/$file_name" "$expected_pages_dir/$file_name"; then
        echo "assembled Pages state differs from the verified site: $file_name" >&2
        exit 65
    fi
    counter=$((counter + 1))
    output_file="$work_dir/file-$counter"
    request_url="$base_url/$file_name?megawhisper_pages=$run_token-$counter"
    response="$(
        curl --silent --show-error --location \
            --proto '=https' --tlsv1.2 \
            --retry 3 --retry-all-errors --retry-delay 1 \
            --connect-timeout 10 --max-time 60 --max-redirs 3 \
            --header 'Cache-Control: no-cache' \
            --output "$output_file" \
            --write-out '%{response_code}\t%{content_type}\t%{url_effective}' \
            "$request_url"
    )"
    IFS=$'\t' read -r response_code content_type effective_url <<< "$response"
    effective_without_query="${effective_url%%\?*}"
    expected_without_query="${request_url%%\?*}"
    effective_origin="${effective_url#https://}"
    effective_origin="${effective_origin%%/*}"
    if [[ "$response_code" != 200 \
          || "$effective_origin" != "$origin" \
          || "$effective_without_query" != "$expected_without_query" \
          || ! -s "$output_file" ]]; then
        echo "live Pages file is unavailable or redirected unexpectedly: $file_name" >&2
        exit 65
    fi
    case "$file_name" in
        *.html)
            [[ "$content_type" == text/html* ]]
            ;;
        *.css)
            [[ "$content_type" == text/css* ]]
            ;;
        *.js)
            [[ "$content_type" == text/javascript* \
                || "$content_type" == application/javascript* ]]
            ;;
        *.svg)
            [[ "$content_type" == image/svg+xml* ]]
            ;;
        *.png)
            [[ "$content_type" == image/png* ]]
            ;;
        *.xml)
            [[ "$content_type" == application/xml* \
                || "$content_type" == text/xml* ]]
            ;;
        *.txt)
            [[ "$content_type" == text/plain* ]]
            ;;
        *.flatpakref|*.flatpakrepo)
            if [[ "$content_type" == text/html* ]]; then
                echo "Flatpak install file resolved to HTML: $file_name" >&2
                exit 65
            fi
            ;;
    esac
    if ! cmp --silent "$expected_site_dir/$file_name" "$output_file"; then
        echo "live Pages file differs from the assembled state: $file_name" >&2
        exit 65
    fi
done

flatpak_commit="$expected_commit"
if [[ "$flatpak_commit" == none ]]; then
    flatpak_commit=""
fi
"$script_dir/verify-live-flatpak-state.sh" \
    "$base_url" "$expected_pages_dir" "$expected_fingerprint" \
    "$flatpak_commit" "$run_token-flatpak"

echo "Live Pages site and Flatpak state verified: mode=$mode commit=$expected_commit"
