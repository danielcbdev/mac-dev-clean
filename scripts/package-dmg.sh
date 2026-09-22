#!/bin/bash
#
# Wraps an already-built app in a drag-to-Applications disk image.
#
# It builds nothing and verifies nothing: the app handed to it is the app that
# ships. Run scripts/verify-artifact.sh first.
set -euo pipefail

HDIUTIL="${MACDEVCLEAN_HDIUTIL:-/usr/bin/hdiutil}"
DITTO="${MACDEVCLEAN_DITTO:-/usr/bin/ditto}"

usage() {
    echo "usage: package-dmg.sh --app <app-path> --output <dmg-path>" >&2
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

# Refused rather than overwritten. The -ov flag below applies only to the
# staging path this script just created, never to something already there.
if [ -e "$output" ]; then
    echo "error: $output already exists. Choose a new output path." >&2
    exit 1
fi

output_directory="$(dirname "$output")"
if [ ! -d "$output_directory" ]; then
    echo "error: no such directory: $output_directory" >&2
    exit 1
fi

stage_dir="$(mktemp -d)"
discard_owned_staging_directory() {
    # Only ever the directory created above, on this run.
    case "$stage_dir" in
        /*/*) [ -d "$stage_dir" ] && rm -rf "$stage_dir" ;;
    esac
}
trap discard_owned_staging_directory EXIT

"$DITTO" "$app" "$stage_dir/MacDevClean.app"
ln -s /Applications "$stage_dir/Applications"

"$HDIUTIL" create \
    -volname MacDevClean \
    -srcfolder "$stage_dir" \
    -ov \
    -format UDZO \
    "$output"

echo "==> Wrote $output"
printf '%s\n' "$output"
