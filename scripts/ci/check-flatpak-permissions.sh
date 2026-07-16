#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $# -ne 0 ]]; then
    echo "usage: flatpak info --show-permissions APP_ID | $0" >&2
    exit 64
fi

permissions="$(cat)"
if ! grep -Fxq '[Context]' <<< "$permissions"; then
    echo "Flatpak permission output has no [Context] section" >&2
    exit 65
fi

if grep -Fxq '[System Bus Policy]' <<< "$permissions"; then
    echo "Flatpak unexpectedly has a system D-Bus policy section" >&2
    exit 65
fi

unknown_sections="$(
    sed -n 's/^\[\([^]]*\)\]$/\1/p' <<< "$permissions" \
        | awk '$0 != "Context" && $0 != "Environment" && $0 != "Session Bus Policy" { print }'
)"
if [[ -n "$unknown_sections" ]]; then
    echo "Flatpak permission output has an unexpected section: $unknown_sections" >&2
    exit 65
fi

context="$(
    awk '
        $0 == "[Context]" { in_context=1; next }
        /^\[/ { in_context=0 }
        in_context && NF { print }
    ' <<< "$permissions"
)"
if [[ -z "$context" ]]; then
    echo "Flatpak [Context] section is empty" >&2
    exit 65
fi

unknown_keys="$(
    awk -F= '$1 != "shared" && $1 != "sockets" && $1 != "devices" && $1 != "filesystems" { print $1 }' \
        <<< "$context"
)"
if [[ -n "$unknown_keys" ]]; then
    echo "Flatpak [Context] has an unexpected key: $unknown_keys" >&2
    exit 65
fi

normalize_set() {
    awk -v RS=';' 'NF { print }' \
        | LC_ALL=C sort -u \
        | awk 'BEGIN { separator="" } { printf "%s%s", separator, $0; separator=";" } END { print "" }'
}

context_value() {
    local key="$1"
    local count
    count="$(awk -F= -v key="$key" '$1 == key { count++ } END { print count + 0 }' \
        <<< "$context")"
    if [[ "$count" -ne 1 ]]; then
        echo "Flatpak [Context] must contain exactly one $key entry" >&2
        exit 65
    fi
    sed -n "s/^${key}=//p" <<< "$context" | normalize_set
}

shared="$(context_value shared)"
sockets="$(context_value sockets)"
devices="$(context_value devices)"
filesystems="$(context_value filesystems)"
readonly shared devices filesystems
# Flatpak 1.14 reports fallback-x11 as both x11 and fallback-x11, while newer
# releases expose only fallback-x11. Canonicalize that legacy pair without
# accepting a standalone broad x11 permission.
if [[ ";$sockets;" == *';x11;'* \
      && ";$sockets;" == *';fallback-x11;'* ]]; then
    sockets="$(
        printf '%s' "$sockets" \
            | awk -v RS=';' '
                $0 != "x11" && NF {
                    printf "%s%s", separator, $0
                    separator=";"
                }
                END { print "" }
            '
    )"
fi
readonly sockets
if [[ "$shared" != 'ipc;network' ]]; then
    echo "Flatpak shared permissions must be exactly ipc and network: $shared" >&2
    exit 65
fi
if [[ "$sockets" != 'fallback-x11;pulseaudio;wayland' ]]; then
    echo "Flatpak sockets must be exactly fallback-x11, pulseaudio and wayland: $sockets" >&2
    exit 65
fi
if [[ "$devices" != 'dri' ]]; then
    echo "Flatpak devices permission must be exactly dri: $devices" >&2
    exit 65
fi
if [[ "$filesystems" != 'xdg-config/kdeglobals:ro' ]]; then
    echo "Flatpak filesystem permission must be exactly the read-only KDE settings file: $filesystems" >&2
    exit 65
fi

environment="$(
    awk '
        $0 == "[Environment]" { in_environment=1; next }
        /^\[/ { in_environment=0 }
        in_environment && NF { print }
    ' <<< "$permissions" | LC_ALL=C sort
)"
readonly environment
expected_environment="$({
    printf '%s\n' \
        'QT_AUDIO_BACKEND=pulseaudio' \
        'QT_MEDIA_BACKEND=gstreamer' \
        'QT_PLUGIN_PATH=/app/lib/plugins' \
        'SSL_CERT_FILE=/app/share/megawhisper/tls-ca-bundle.pem'
} | LC_ALL=C sort)"
readonly expected_environment
if [[ "$environment" != "$expected_environment" ]]; then
    echo "Flatpak environment differs from the audited runtime configuration:" >&2
    printf '%s\n' "$environment" >&2
    exit 65
fi

session_policy="$(
    awk '
        $0 == "[Session Bus Policy]" { in_policy=1; next }
        /^\[/ { in_policy=0 }
        in_policy && NF { print }
    ' <<< "$permissions"
)"
if [[ -z "$session_policy" ]]; then
    echo "Flatpak is missing the KDE runtime session D-Bus policy" >&2
    exit 65
fi

expected_session_policy="$({
    printf '%s\n' \
        'com.canonical.AppMenu.Registrar=talk' \
        'org.kde.KGlobalSettings=talk' \
        'org.kde.StatusNotifierWatcher=talk' \
        'org.kde.kconfig.notify=talk'
} | LC_ALL=C sort)"
actual_session_policy="$(LC_ALL=C sort <<< "$session_policy")"
readonly session_policy expected_session_policy actual_session_policy
if [[ "$actual_session_policy" != "$expected_session_policy" ]]; then
    echo "Flatpak session D-Bus policy differs from the audited KDE runtime policy:" >&2
    printf '%s\n' "$session_policy" >&2
    exit 65
fi
