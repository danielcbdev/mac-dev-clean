#!/bin/bash
#
# Builds an unsigned universal MacDevClean.app for local use.
#
# This produces a development artifact. It is not signed, not notarized, and
# macOS will say so when it is opened. See docs/release/manual-install.md.
#
# Every external tool is resolved through a variable so the contract tests can
# inject a fixture executable without touching the caller's PATH.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
XCODEBUILD="${MACDEVCLEAN_XCODEBUILD:-xcodebuild}"
DITTO="${MACDEVCLEAN_DITTO:-/usr/bin/ditto}"
DERIVED_DATA="${MACDEVCLEAN_DERIVED_DATA:-$ROOT/.build/package}"

usage() {
    echo "usage: build-local.sh --version <major.minor.patch> --output <directory>" >&2
}

version=""
output=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --version) version="${2:-}"; shift 2 ;;
        --output) output="${2:-}"; shift 2 ;;
        *) usage; exit 2 ;;
    esac
done

if [ -z "$version" ] || [ -z "$output" ]; then
    usage
    exit 2
fi

# The version reaches xcodebuild as a build setting. Anything but three
# numbers is refused rather than passed along, so no shell fragment or
# setting override can ride in on it.
if ! printf '%s' "$version" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "error: --version must be major.minor.patch, got: $version" >&2
    exit 2
fi

staged="$output/MacDevClean.app"
if [ -e "$staged" ]; then
    echo "error: $staged already exists. Choose an empty output directory." >&2
    exit 1
fi

# Monotonic, and derived from the clock rather than from a counter nobody
# increments: a later build always sorts above an earlier one.
build_number="$(date -u +%Y%m%d%H%M)"

echo "==> Building MacDevClean $version ($build_number), unsigned, arm64 + x86_64"
"$XCODEBUILD" \
    -workspace "$ROOT/MacDevClean.xcworkspace" \
    -scheme MacDevClean \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$DERIVED_DATA" \
    ARCHS='arm64 x86_64' \
    ONLY_ACTIVE_ARCH=NO \
    MACOSX_DEPLOYMENT_TARGET=14.0 \
    MARKETING_VERSION="$version" \
    CURRENT_PROJECT_VERSION="$build_number" \
    CODE_SIGNING_ALLOWED=NO \
    build

built="$DERIVED_DATA/Build/Products/Release/MacDevClean.app"
if [ ! -d "$built" ]; then
    echo "error: the build reported success but produced no app at $built" >&2
    exit 1
fi

mkdir -p "$output"
"$DITTO" "$built" "$staged"

echo "==> Staged $staged"
printf '%s\n' "$staged"
