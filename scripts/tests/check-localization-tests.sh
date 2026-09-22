#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
checker="$root/scripts/check-localization.swift"
fixtures="$root/scripts/tests/fixtures"

swift "$checker" "$fixtures/localization-valid.xcstrings"

# One fixture per rule. A checker with no rejected fixture is a checker that
# has never been shown to reject anything.
for fixture in \
    localization-missing.xcstrings \
    localization-plural-mismatch.xcstrings \
    localization-inflection.xcstrings \
    localization-no-plural.xcstrings \
    localization-category-mismatch.xcstrings \
    localization-empty-variation.xcstrings
do
    if swift "$checker" "$fixtures/$fixture"; then
        echo "Expected $fixture to fail validation" >&2
        exit 1
    fi
done

echo "Localization checker rejected every invalid fixture"
