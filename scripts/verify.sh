#!/bin/bash
#
# The full local gate. Exits 0 only if every check passed.
#
# Signing note: the Debug test action is *not* run with CODE_SIGNING_ALLOWED=NO.
# On Apple Silicon an unsigned XCUITest runner is killed before it can connect,
# so the UI tests never start. The project signs ad hoc (CODE_SIGN_IDENTITY "-",
# no team), which needs no Apple account. See docs/adr/0002-toolchain.md.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "==> Toolchain"
xcodebuild -version
swift --version

echo "==> Swift package tests"
swift test --package-path Packages/MacDevCleanCore

echo "==> App tests (Debug, ad-hoc signed so the UI test runner can launch)"
xcodebuild -workspace MacDevClean.xcworkspace -scheme MacDevClean \
    -destination 'platform=macOS' -derivedDataPath .build/xcode test

echo "==> Release build (unsigned)"
xcodebuild -workspace MacDevClean.xcworkspace -scheme MacDevClean \
    -configuration Release -destination 'platform=macOS' \
    -derivedDataPath .build/release build CODE_SIGNING_ALLOWED=NO

echo "==> Lint"
bash scripts/lint.sh

echo "==> Whitespace"
git diff --check

echo "==> verify.sh: all checks passed"
