#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
checker="$root/scripts/check-localization.swift"
fixtures="$root/scripts/tests/fixtures"

swift "$checker" "$fixtures/localization-valid.xcstrings"

for fixture in localization-missing.xcstrings localization-plural-mismatch.xcstrings; do
    if swift "$checker" "$fixtures/$fixture"; then
        echo "Expected $fixture to fail validation" >&2
        exit 1
    fi
done
