#!/bin/bash
#
# Proves that cleanup authority cannot be minted from outside the Cleanup
# target.
#
# `ValidatedCleanupItem` and `ValidatedCleanupPlan` have internal initialisers
# and no decoding, so the executor's input can only have come from the
# validator. That is an access-control claim, and access control is exactly the
# kind of thing that quietly stops being true during a refactor. This check
# type-checks two fixtures against the real built modules:
#
#   ForgedToken     must FAIL, with a diagnostic about inaccessibility.
#   PublicConsumer  must SUCCEED, proving the public surface still works and
#                   that the failure above is about access, not a broken fixture.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PACKAGE="Packages/MacDevCleanCore"
FIXTURES="$PACKAGE/Tests/CleanupTests/CompileFailures"

echo "==> Building modules"
swift build --package-path "$PACKAGE" >/dev/null
BIN="$(swift build --package-path "$PACKAGE" --show-bin-path)"

# Inside the ignored build directory, so nothing needs deleting afterwards and
# nothing outside the project is touched.
SCRATCH="$PACKAGE/.build/token-access"
mkdir -p "$SCRATCH"

typecheck() {
    local fixture="$1"
    local source="$SCRATCH/$(basename "${fixture%.fixture}")"
    cp "$fixture" "$source"
    xcrun swiftc -typecheck \
        -swift-version 6 \
        -target "$(uname -m)-apple-macos14.0" \
        -I "$BIN" \
        -F "$BIN/PackageFrameworks" \
        "$source" 2>&1
}

echo "==> The public surface must remain usable from outside Cleanup"
if ! output="$(typecheck "$FIXTURES/PublicConsumer.swift.fixture")"; then
    echo "error: the public consumer fixture failed to type-check." >&2
    echo "       The public API of Cleanup is broken, or this check needs updating." >&2
    echo "$output" >&2
    exit 1
fi
echo "PublicConsumer: type-checks, as required"

echo "==> Forging a validated plan from outside Cleanup must fail"
if output="$(typecheck "$FIXTURES/ForgedToken.swift.fixture")"; then
    echo "error: ForgedToken type-checked." >&2
    echo "       Cleanup authority can now be constructed outside the Cleanup" >&2
    echo "       target, which defeats the validator entirely." >&2
    exit 1
fi

# It must fail for the right reason. Any other compiler error would pass this
# check by accident while proving nothing.
if ! grep -qiE "inaccessible|not available|cannot be constructed" <<<"$output"; then
    echo "error: ForgedToken failed to compile, but not because of access control." >&2
    echo "       This check only means something if the diagnostic is about" >&2
    echo "       inaccessibility. Compiler said:" >&2
    echo "$output" >&2
    exit 1
fi

echo "ForgedToken: rejected as inaccessible, as required"
echo "check-token-access.sh: the cleanup authority boundary holds"
