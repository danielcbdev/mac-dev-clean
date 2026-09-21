#!/bin/bash
set -euo pipefail

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
    matches="$(rg -n --glob '*.swift' -- "$pattern" "${sources[@]}" || true)"
    if [ -n "$matches" ]; then
        echo "Policy check failed: $description" >&2
        echo "$matches" >&2
        exit 1
    fi
}

fail_if_found "filesystem cleanup must not call FileManager.removeItem" \
    'FileManager\.default\.removeItem\s*\('
fail_if_found "filesystem cleanup must not call rm, rmdir, unlink, or deleteFile" \
    '\b(rm|rmdir|unlink|deleteFile)\s*\('
fail_if_found "Docker integration must not invoke a shell executable" \
    'fileURLWithPath:\s*"/(bin|usr/bin)/(sh|bash|zsh)"'
fail_if_found "production code must not contain a private home path" \
    '"/Users/'
fail_if_found "production code must not import telemetry SDKs" \
    '^import (Amplitude|Mixpanel|Segment|Telemetry)'

echo "Policy check passed"
