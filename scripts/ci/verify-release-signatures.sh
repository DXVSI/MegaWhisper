#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $# -ne 4 ]]; then
    echo "usage: $0 ARTIFACT_DIR VERSION binary-v1 EXPECTED_FINGERPRINT" >&2
    exit 64
fi

artifact_dir="$(realpath "$1")"
readonly version="$2"
readonly asset_schema="$3"
readonly expected_fingerprint="${4^^}"
readonly artifact_dir
if [[ ! "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
    echo "release verification version must be a stable semantic version" >&2
    exit 64
fi
if [[ "$asset_schema" != binary-v1 ]]; then
    echo "asset schema must be binary-v1" >&2
    exit 64
fi
if [[ ! "$expected_fingerprint" =~ ^([0-9A-F]{40}|[0-9A-F]{64})$ ]]; then
    echo "expected release fingerprint has an invalid format" >&2
    exit 64
fi
IFS=. read -r version_major version_minor _ <<< "$version"
if (( 10#$version_major < 2 \
      || (10#$version_major == 2 && 10#$version_minor < 1) )); then
    echo "binary-v1 requires version 2.1.0 or newer" >&2
    exit 64
fi
for required_file in megawhisper-release-key.asc SHA256SUMS SHA256SUMS.asc; do
    if [[ ! -f "$artifact_dir/$required_file" \
          || -L "$artifact_dir/$required_file" \
          || ! -s "$artifact_dir/$required_file" ]]; then
        echo "required signed release file is missing: $required_file" >&2
        exit 66
    fi
done

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly script_dir
list_mode=release
payload_mode=payload
readonly list_mode payload_mode
expected_assets="$(
    "$script_dir/list-release-assets.sh" "$version" "$list_mode"
)"
actual_assets="$(find "$artifact_dir" -mindepth 1 -maxdepth 1 \
    -type f -printf '%f\n' | LC_ALL=C sort)"
invalid_entries="$(find "$artifact_dir" -mindepth 1 -maxdepth 1 \
    ! -type f -print -quit)"
if [[ -n "$invalid_entries" || "$actual_assets" != "$expected_assets" ]]; then
    echo "release asset inventory does not match $asset_schema" >&2
    diff -u <(printf '%s\n' "$expected_assets") \
        <(printf '%s\n' "$actual_assets") >&2 || true
    exit 65
fi

verify_home="$(mktemp -d)"
bundle_root="$(mktemp -d)"
readonly verify_home bundle_root
cleanup() {
    gpgconf --homedir "$verify_home" --kill all >/dev/null 2>&1 || true
    rm -rf "$verify_home" "$bundle_root"
}
trap cleanup EXIT
chmod 0700 "$verify_home"
mapfile -t public_fingerprints < <(
    gpg --batch --with-colons --show-keys \
        "$artifact_dir/megawhisper-release-key.asc" \
        | awk -F: '
            $1 == "pub" { want_primary=1; next }
            $1 == "fpr" && want_primary {
                print toupper($10)
                want_primary=0
            }
        '
)
if [[ "${#public_fingerprints[@]}" -ne 1 \
      || "${public_fingerprints[0]}" != "$expected_fingerprint" ]]; then
    echo "release public key does not match the pinned fingerprint" >&2
    exit 65
fi
gpg --batch --homedir "$verify_home" \
    --import "$artifact_dir/megawhisper-release-key.asc"
gpg --batch --homedir "$verify_home" \
    --verify "$artifact_dir/SHA256SUMS.asc" "$artifact_dir/SHA256SUMS"

checksum_names="$(awk '
    NF != 2 || $1 !~ /^[0-9a-f]{64}$/ || substr($2, 1, 1) != "*" {
        exit 65
    }
    {
        name=substr($2, 2)
        if (name == "" || name ~ /\// || name ~ /^\./) exit 65
        print name
    }
' "$artifact_dir/SHA256SUMS" | LC_ALL=C sort)" || {
    echo "binary-v1 SHA256SUMS has an invalid entry" >&2
    exit 65
}
expected_checksum_names="$(
    "$script_dir/list-release-assets.sh" "$version" "$payload_mode"
)"
if [[ "$checksum_names" != "$expected_checksum_names" ]]; then
    echo "signed checksum inventory does not match $asset_schema" >&2
    exit 65
fi
(
    cd "$artifact_dir"
    sha256sum --check --strict SHA256SUMS
)

compliance_dir="$bundle_root/third-party-compliance"
recovery_dir="$bundle_root/recovery"
"$script_dir/release-bundles.sh" extract third-party-compliance "$version" \
    "$artifact_dir/MegaWhisper-$version-third-party-compliance.tar.zst" \
    "$compliance_dir"
"$script_dir/release-bundles.sh" extract recovery "$version" \
    "$artifact_dir/MegaWhisper-$version-recovery.tar.zst" \
    "$recovery_dir"
if ! cmp --silent \
    "$artifact_dir/megawhisper-release-key.asc" \
    "$recovery_dir/megawhisper-release-key.asc"; then
    echo "top-level and recovery release keys differ" >&2
    exit 65
fi
while IFS= read -r file_name; do
    if [[ "$file_name" == *.asc \
          || "$file_name" == megawhisper-release-key.asc ]]; then
        continue
    fi
    gpg --batch --homedir "$verify_home" \
        --verify "$recovery_dir/$file_name.asc" \
        "$recovery_dir/$file_name"
done < <("$script_dir/list-release-assets.sh" "$version" recovery-input)

echo "Verified binary-v1 release checksums, bundles and recovery signatures"
