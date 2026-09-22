#!/bin/bash
#
# Signs, notarizes and staples an already-tested app, then produces a signed,
# notarized, stapled disk image.
#
# It builds nothing and it tests nothing. The app handed to it is the app that
# ships. Every failure is terminal: there is no path through this script that
# publishes something unsigned, unnotarized or unverified.
#
# Secrets arrive in the environment, are written to files only the current user
# can read, and are never printed. The keychain search list is restored and the
# temporary keychain deleted on every exit, including failure.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SECURITY="${MACDEVCLEAN_SECURITY:-/usr/bin/security}"
CODESIGN="${MACDEVCLEAN_CODESIGN:-/usr/bin/codesign}"
NOTARYTOOL="${MACDEVCLEAN_NOTARYTOOL:-xcrun notarytool}"
STAPLER="${MACDEVCLEAN_STAPLER:-xcrun stapler}"
SPCTL="${MACDEVCLEAN_SPCTL:-/usr/sbin/spctl}"
DITTO="${MACDEVCLEAN_DITTO:-/usr/bin/ditto}"
PLUTIL="${MACDEVCLEAN_PLUTIL:-/usr/bin/plutil}"

usage() {
    echo "usage: sign-notarize.sh --app <app-path> --output <dmg-path>" >&2
}

app=""
output=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --app) app="${2:-}"; shift 2 ;;
        --output) output="${2:-}"; shift 2 ;;
        *) usage; exit 2 ;;
    esac
done

if [ -z "$app" ] || [ -z "$output" ]; then
    usage
    exit 2
fi
if [ ! -d "$app" ] || [ ! -f "$app/Contents/Info.plist" ]; then
    echo "error: not an app bundle: $app" >&2
    exit 1
fi
if [ -e "$output" ]; then
    echo "error: $output already exists. Choose a new output path." >&2
    exit 1
fi

# No credentials, no release. This is the only gate that decides it.
bash "$ROOT/scripts/release-preflight.sh" --mode public

work="$(mktemp -d)"
keychain="$work/macdevclean-release.keychain-db"
keychain_password="$(uuidgen)"
original_keychains="$("$SECURITY" list-keychains -d user | tr -d '"' | xargs || true)"

restore_the_machine_as_it_was() {
    if [ -n "$original_keychains" ]; then
        # shellcheck disable=SC2086
        "$SECURITY" list-keychains -d user -s $original_keychains >/dev/null 2>&1 || true
    fi
    [ -f "$keychain" ] && "$SECURITY" delete-keychain "$keychain" >/dev/null 2>&1
    case "$work" in
        /*/*) [ -d "$work" ] && rm -rf "$work" ;;
    esac
}
trap restore_the_machine_as_it_was EXIT

umask 077
certificate="$work/certificate.p12"
api_key="$work/api-key.p8"
printf '%s' "$APPLE_CERTIFICATE_P12_BASE64" | base64 --decode > "$certificate"
printf '%s' "$APPLE_API_PRIVATE_KEY" > "$api_key"
chmod 600 "$certificate" "$api_key"

echo "==> Preparing a temporary keychain"
"$SECURITY" create-keychain -p "$keychain_password" "$keychain"
"$SECURITY" set-keychain-settings -lut 21600 "$keychain"
"$SECURITY" unlock-keychain -p "$keychain_password" "$keychain"
# `security import` takes the password as an argument; there is no file or
# stdin form. On an ephemeral single-tenant runner that is acceptable. Do not
# run this script on a shared machine.
"$SECURITY" import "$certificate" -k "$keychain" -P "$APPLE_CERTIFICATE_PASSWORD" \
    -T "$CODESIGN" -x
"$SECURITY" set-key-partition-list -S apple-tool:,apple: -s -k "$keychain_password" \
    "$keychain" >/dev/null
# shellcheck disable=SC2086
"$SECURITY" list-keychains -d user -s "$keychain" $original_keychains

identity="$("$SECURITY" find-identity -v -p codesigning "$keychain" \
    | grep "Developer ID Application" \
    | grep "($APPLE_TEAM_ID)" \
    | head -1 \
    | sed -E 's/.*"(.*)".*/\1/')"
if [ -z "$identity" ]; then
    echo "error: no Developer ID Application identity for team $APPLE_TEAM_ID" >&2
    exit 1
fi
echo "==> Signing as a Developer ID Application identity for team $APPLE_TEAM_ID"

# Nested code first, outermost last. --deep is not used: it signs whatever it
# finds with one set of options, which is how a nested component silently ends
# up with the wrong entitlements.
nested="$(find "$app/Contents" -maxdepth 3 \( -name '*.framework' -o -name '*.dylib' \
    -o -name '*.xpc' -o -name '*.appex' \) 2>/dev/null || true)"
if [ -n "$nested" ]; then
    while IFS= read -r component; do
        [ -n "$component" ] || continue
        echo "    nested: $component"
        "$CODESIGN" --force --options runtime --timestamp --sign "$identity" "$component"
    done <<< "$nested"
fi

"$CODESIGN" --force --options runtime --timestamp --sign "$identity" "$app"
"$CODESIGN" --verify --deep --strict --verbose=2 "$app"

notarize() {
    local target="$1"
    local response
    response="$($NOTARYTOOL submit "$target" \
        --key "$api_key" \
        --key-id "$APPLE_API_KEY_ID" \
        --issuer "$APPLE_API_ISSUER_ID" \
        --wait \
        --output-format json)"
    local status
    status="$(printf '%s' "$response" | "$PLUTIL" -extract status raw -o - - 2>/dev/null || true)"
    if [ "$status" != "Accepted" ]; then
        echo "error: notarization did not return Accepted (got: ${status:-unparseable})" >&2
        return 1
    fi
    echo "    notarization: Accepted"
}

echo "==> Notarizing the application"
submission_zip="$work/MacDevClean.zip"
"$DITTO" -c -k --keepParent "$app" "$submission_zip"
notarize "$submission_zip"
$STAPLER staple "$app"
$STAPLER validate "$app"
"$SPCTL" --assess --type execute --verbose=2 "$app"

echo "==> Packaging the signed application"
MACDEVCLEAN_DITTO="$DITTO" bash "$ROOT/scripts/package-dmg.sh" --app "$app" --output "$output"

echo "==> Signing and notarizing the disk image"
"$CODESIGN" --force --timestamp --sign "$identity" "$output"
notarize "$output"
$STAPLER staple "$output"
$STAPLER validate "$output"

MACDEVCLEAN_CODESIGN="$CODESIGN" bash "$ROOT/scripts/verify-artifact.sh" \
    --app "$app" --mode signed

echo "==> Signed, notarized and stapled: $output"
printf '%s\n' "$output"
