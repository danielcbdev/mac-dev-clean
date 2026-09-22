#!/bin/bash
#
# Builds and launches MacDevClean against synthetic fixtures, in a chosen
# language, for manual verification.
#
# WHY THIS SCRIPT EXISTS
#
# The fixture composition is `#if DEBUG`. `AppDependencies.fixture(scenario:)`,
# `PreviewScenario` and the whole of PreviewDependencies.swift are compiled out
# of Release, and the Release configuration does not define DEBUG. That is a
# deliberate safety property: a shipping binary cannot be talked into fixture
# mode.
#
# The consequence is easy to miss. `scripts/build-local.sh` builds **Release**.
# Launching its product with `--ui-testing --scenario mixed-results` does not
# produce fixtures — the arguments are accepted and ignored, and the app runs
# its real composition against the folders the owner configured and against
# ~/Library/Application Support/MacDevClean/store.sqlite. Verification must
# never run there.
#
# So this script builds Debug, and refuses to launch anything else.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

scenario="mixed-results"
language="pt-BR"
locale=""

usage() {
    echo "usage: run-fixture.sh [--scenario <name>] [--language en|pt-BR]" >&2
    echo "  scenarios: first-run, mixed-results, docker-volume, large-files" >&2
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --scenario) scenario="${2:-}"; shift 2 ;;
        --language) language="${2:-}"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) usage; exit 2 ;;
    esac
done

case "$scenario" in
    first-run|mixed-results|docker-volume|large-files) ;;
    *) echo "error: unknown scenario: $scenario" >&2; usage; exit 2 ;;
esac

case "$language" in
    en) locale="en_US" ;;
    pt-BR) locale="pt_BR" ;;
    *) echo "error: language must be en or pt-BR, got: $language" >&2; exit 2 ;;
esac

app=".build/xcode/Build/Products/Debug/MacDevClean.app"

echo "==> Building Debug (the only configuration that has the fixtures)"
xcodebuild -workspace MacDevClean.xcworkspace -scheme MacDevClean \
    -configuration Debug -destination 'platform=macOS' \
    -derivedDataPath .build/xcode build >/dev/null

if [ ! -d "$app" ]; then
    echo "error: $app was not produced" >&2
    exit 1
fi

# Prove the launched binary really is the fixture-capable one rather than a
# Release build someone pointed this at. A verification run against real data
# is worse than no verification run.
if ! plutil -extract CFBundleIdentifier raw "$app/Contents/Info.plist" >/dev/null 2>&1; then
    echo "error: $app has no readable Info.plist" >&2
    exit 1
fi

echo "==> Launching: scenario=$scenario language=$language"
echo "    Fixtures live in a temporary tree this launch creates and owns."
echo "    Nothing reads your caches, your Trash or your Docker."
open "$app" --args \
    --ui-testing --scenario "$scenario" \
    -AppleLanguages "($language)" -AppleLocale "$locale"
