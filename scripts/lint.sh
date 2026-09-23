#!/bin/bash
#
# Read-only style check. Run `xcrun swift-format format --in-place` yourself to
# fix findings; this script never rewrites your files.
#
# The formatter comes from the tested Xcode toolchain, so CI uses exactly the
# version pinned in docs/adr/0002-toolchain.md. Nothing is downloaded.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if ! xcrun --find swift-format >/dev/null 2>&1; then
    echo "error: swift-format not found in the active Xcode toolchain." >&2
    echo "       Active developer directory: $(xcode-select -p)" >&2
    exit 1
fi

echo "swift-format: $(xcrun --find swift-format)"

SOURCE_ROOTS=(
    "Packages/MacDevCleanCore/Sources"
    "Packages/MacDevCleanCore/Tests"
    "MacDevCleanApp"
    "MacDevCleanUITests"
)

PRESENT=()
for path in "${SOURCE_ROOTS[@]}"; do
    if [ -d "$path" ]; then
        PRESENT+=("$path")
    fi
done

if [ ${#PRESENT[@]} -eq 0 ]; then
    echo "error: no Swift source roots found." >&2
    exit 1
fi

xcrun swift-format lint --strict --recursive --configuration .swift-format "${PRESENT[@]}"
echo "lint: no findings"
