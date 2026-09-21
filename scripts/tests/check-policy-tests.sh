#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
checker="$root/scripts/check-policy.sh"
fixtures="$root/scripts/tests/fixtures"

bash "$checker" "$fixtures/policy-valid"
if bash "$checker" "$fixtures/policy-remove-item"; then
    echo "Expected FileManager.removeItem fixture to fail policy validation" >&2
    exit 1
fi
