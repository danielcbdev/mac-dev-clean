#!/bin/bash
#
# The full local gate. Exits 0 only if every check that ran passed, and it never
# reports a check that did not run as a pass.
#
# Signing note: the Debug test action is *not* run with CODE_SIGNING_ALLOWED=NO.
# On Apple Silicon an unsigned XCUITest runner is killed before it can connect,
# so the UI tests never start. The project signs ad hoc (CODE_SIGN_IDENTITY "-",
# no team), which needs no Apple account. See docs/adr/0002-toolchain.md.
#
# UI tests need a logged-in, interactive macOS session where an app can be
# launched and inspected through the accessibility interface. When that is not
# available, set MACDEVCLEAN_SKIP_UI_TESTS=1: the gate then reports the UI suite
# as NOT RUN and says so loudly. It is a missing gate, never a pass.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "==> Toolchain"
xcodebuild -version
swift --version

echo "==> Swift package tests"
swift test --package-path Packages/MacDevCleanCore

echo "==> App unit tests (Debug, ad-hoc signed)"
xcodebuild -workspace MacDevClean.xcworkspace -scheme MacDevClean \
    -destination 'platform=macOS' -derivedDataPath .build/xcode \
    -only-testing:MacDevCleanAppTests test

if [ "${MACDEVCLEAN_SKIP_UI_TESTS:-0}" = "1" ]; then
    echo "==> UI tests: NOT RUN"
    echo "    MACDEVCLEAN_SKIP_UI_TESTS=1 was set. This is a MISSING GATE, not a pass."
    echo "    Record it as not run in docs/verification/, with the reason."
else
    echo "==> UI tests (Debug, ad-hoc signed so the runner can launch)"
    xcodebuild -workspace MacDevClean.xcworkspace -scheme MacDevClean \
        -destination 'platform=macOS' -derivedDataPath .build/xcode \
        -only-testing:MacDevCleanUITests test
fi

echo "==> Release build (unsigned)"
xcodebuild -workspace MacDevClean.xcworkspace -scheme MacDevClean \
    -configuration Release -destination 'platform=macOS' \
    -derivedDataPath .build/release build CODE_SIGNING_ALLOWED=NO

echo "==> Cleanup authority boundary"
bash scripts/check-token-access.sh

echo "==> Localization catalog"
bash scripts/tests/check-localization-tests.sh
swift scripts/check-localization.swift

echo "==> Static cleanup and privacy policy"
bash scripts/tests/check-policy-tests.sh
bash scripts/check-policy.sh

echo "==> Lint"
bash scripts/lint.sh

echo "==> Whitespace"
git diff --check

if [ "${MACDEVCLEAN_SKIP_UI_TESTS:-0}" = "1" ]; then
    echo "==> verify.sh: all checks that ran passed — UI tests NOT RUN"
else
    echo "==> verify.sh: all checks passed"
fi
