#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $# -ne 1 ]]; then
    echo "usage: $0 ARTIFACT_DIR" >&2
    exit 64
fi

artifact_dir="$(realpath "$1")"
readonly artifact_dir
for required_file in megawhisper-release-key.asc SHA256SUMS SHA256SUMS.asc; do
    if [[ ! -s "$artifact_dir/$required_file" ]]; then
        echo "required signed release file is missing: $required_file" >&2
        exit 66
    fi
done

verify_home="$(mktemp -d)"
readonly verify_home
trap 'rm -rf "$verify_home"' EXIT
chmod 0700 "$verify_home"
gpg --batch --homedir "$verify_home" --import "$artifact_dir/megawhisper-release-key.asc"
gpg --batch --homedir "$verify_home" \
    --verify "$artifact_dir/SHA256SUMS.asc" "$artifact_dir/SHA256SUMS"

while read -r _ file_name; do
    if [[ -z "$file_name" || "$file_name" == */* || "$file_name" == .* ]]; then
        echo "unsafe entry in SHA256SUMS: $file_name" >&2
        exit 65
    fi
    [[ -s "$artifact_dir/$file_name" ]] || {
        echo "file from SHA256SUMS is missing: $file_name" >&2
        exit 66
    }
done < "$artifact_dir/SHA256SUMS"
(
    cd "$artifact_dir"
    sha256sum --check --strict SHA256SUMS
)

while IFS= read -r -d '' payload; do
    signature="$payload.asc"
    [[ -s "$signature" ]] || {
        echo "detached signature is missing: $(basename "$signature")" >&2
        exit 66
    }
    gpg --batch --homedir "$verify_home" --verify "$signature" "$payload"
done < <(
    find "$artifact_dir" -maxdepth 1 -type f \
        ! -name '*.asc' \
        ! -name 'SHA256SUMS' \
        -print0
)

echo "Release checksums and detached signatures verified"
