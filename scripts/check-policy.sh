#!/bin/bash
#
# Static policy check over production Swift sources.
#
# Engine note: this check originally shelled out to ripgrep. ripgrep is not
# installed on every machine that runs the gate, and `rg ... || true` turned a
# missing binary into "no matches", which printed "Policy check passed" while
# checking nothing. It now uses POSIX grep, which ships with macOS, and refuses
# to run if even that is unavailable. A check that cannot run must fail, never
# pass. The patterns are POSIX extended regular expressions, so ripgrep would
# accept them unchanged.
#
# This is a static complement to the behavioral tests. It proves no production
# Swift file *mentions* these constructs; it does not prove the application is
# safe. That is what the Cleanup and DockerIntegration suites are for.
set -euo pipefail

if ! command -v grep >/dev/null 2>&1; then
    echo "Policy check failed: grep is required and was not found" >&2
    exit 1
fi

root="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

sources=()
for candidate in \
    "$root/Sources" \
    "$root/Packages/MacDevCleanCore/Sources/Cleanup" \
    "$root/Packages/MacDevCleanCore/Sources/DockerIntegration" \
    "$root/MacDevCleanApp"
do
    [ -d "$candidate" ] && sources+=("$candidate")
done

if [ "${#sources[@]}" -eq 0 ]; then
    echo "Policy check failed: no production source directories under $root" >&2
    exit 1
fi

fail_if_found() {
    local description="$1"
    local pattern="$2"
    local matches
    matches="$(grep -R -E -n --include='*.swift' -- "$pattern" "${sources[@]}" || true)"
    if [ -n "$matches" ]; then
        echo "Policy check failed: $description" >&2
        echo "$matches" >&2
        exit 1
    fi
}

fail_if_found "filesystem cleanup must not call FileManager.removeItem" \
    'FileManager\.default\.removeItem[[:space:]]*\('
fail_if_found "filesystem cleanup must not call rm, rmdir, unlink, or deleteFile" \
    '(^|[^A-Za-z0-9_])(rm|rmdir|unlink|deleteFile)[[:space:]]*\('
fail_if_found "Docker integration must not invoke a shell executable" \
    'fileURLWithPath:[[:space:]]*"/(bin|usr/bin)/(sh|bash|zsh)"'
fail_if_found "production code must not contain a private home path" \
    '"/Users/'
fail_if_found "production code must not import telemetry SDKs" \
    '^import (Amplitude|Mixpanel|Segment|Telemetry)'
# The product is offline. This makes that claim checkable instead of implicit:
# a networking API cannot appear in production code without failing the gate.
fail_if_found "production code must not use a networking API" \
    '(^import (Network|CFNetwork|NetworkExtension)|URLSession|NSURLConnection|CFSocket)'

echo "Policy check passed"
