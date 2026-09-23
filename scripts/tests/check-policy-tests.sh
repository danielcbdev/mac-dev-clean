#!/bin/bash
#
# Regression tests for scripts/check-policy.sh.
#
# Each rule gets a fixture that must be rejected. Without them a checker that
# silently matches nothing — a missing search engine, a broken pattern dialect —
# would report every rule as passing. That failure mode is the reason these
# tests exist.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
checker="$root/scripts/check-policy.sh"
fixtures="$root/scripts/tests/fixtures"

expect_rejected() {
    local fixture="$1"
    local description="$2"
    if bash "$checker" "$fixtures/$fixture" >/dev/null 2>&1; then
        echo "Expected $fixture to fail policy validation: $description" >&2
        exit 1
    fi
}

# A clean tree passes, including near misses the rules must not over-match.
bash "$checker" "$fixtures/policy-valid"

expect_rejected policy-remove-item "FileManager.removeItem in cleanup source"
expect_rejected policy-unlink "a raw unlink call"
expect_rejected policy-shell-exec "a shell executable in Docker integration"
expect_rejected policy-private-path "a hardcoded private home path"
expect_rejected policy-telemetry "a telemetry SDK import"
expect_rejected policy-networking "a networking API in production code"
expect_rejected policy-inflection "inline inflection markup in a user-visible string"

# A tree with no production sources at all is a failure, not a vacuous pass.
# The directory is created here, stays empty, and is removed non-recursively.
empty="$(mktemp -d)"
trap 'rmdir "$empty" 2>/dev/null || true' EXIT
if bash "$checker" "$empty" >/dev/null 2>&1; then
    echo "Expected a tree with no production sources to fail" >&2
    exit 1
fi

echo "check-policy tests passed"
