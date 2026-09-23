#!/bin/bash
#
# Checks what an artifact actually promises, before anyone installs it.
#
# --mode unsigned is for the local development build. It checks the bundle and
# says nothing about signing.
# --mode signed additionally requires a real Developer ID Application
# authority. Ad-hoc signing satisfies `codesign --verify` and is *not* a
# distribution signature; treating it as one is the mistake this script exists
# to prevent.
set -euo pipefail

LIPO="${MACDEVCLEAN_LIPO:-/usr/bin/lipo}"
CODESIGN="${MACDEVCLEAN_CODESIGN:-/usr/bin/codesign}"
PLUTIL="${MACDEVCLEAN_PLUTIL:-/usr/bin/plutil}"

usage() {
    echo "usage: verify-artifact.sh --app <app-path> --mode unsigned|signed" >&2
}

app=""
mode=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --app) app="${2:-}"; shift 2 ;;
        --mode) mode="${2:-}"; shift 2 ;;
        *) usage; exit 2 ;;
    esac
done

if [ -z "$app" ] || [ -z "$mode" ]; then
    usage
    exit 2
fi
case "$mode" in
    unsigned|signed) ;;
    *) usage; exit 2 ;;
esac

failures=0
fail() {
    echo "  refused: $1" >&2
    failures=$((failures + 1))
}
pass() {
    echo "  ok: $1"
}

plist="$app/Contents/Info.plist"
if [ ! -d "$app" ] || [ ! -f "$plist" ]; then
    echo "error: not an app bundle: $app" >&2
    exit 1
fi

value_for() {
    "$PLUTIL" -extract "$1" raw -o - "$plist" 2>/dev/null || true
}

echo "==> Verifying $app ($mode)"

# The executable named in the bundle must be the one that is there.
executable="$(value_for CFBundleExecutable)"
if [ -z "$executable" ]; then
    fail "Info.plist declares no CFBundleExecutable"
elif [ ! -x "$app/Contents/MacOS/$executable" ]; then
    fail "CFBundleExecutable does not resolve to an executable: $executable"
else
    pass "executable resolves: $executable"
fi

display_name="$(value_for CFBundleName)"
if [ "$display_name" != "MacDevClean" ]; then
    fail "unexpected application name: ${display_name:-<missing>}"
else
    pass "application name: $display_name"
fi

version="$(value_for CFBundleShortVersionString)"
if ! printf '%s' "$version" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    fail "version is not a semantic version: ${version:-<missing>}"
else
    pass "version: $version"
fi

minimum="$(value_for LSMinimumSystemVersion)"
if [ "$minimum" != "14.0" ]; then
    fail "minimum system version is ${minimum:-<missing>}, expected 14.0"
else
    pass "minimum system version: $minimum"
fi

icon="$(value_for CFBundleIconName)"
if [ -z "$icon" ]; then
    fail "the bundle declares no application icon"
else
    pass "icon: $icon"
fi

# Both architectures, which is a statement about what compiled, not about what
# has been run. docs/testing/manual-release-checks.md keeps those apart.
if [ -n "$executable" ] && [ -f "$app/Contents/MacOS/$executable" ]; then
    architectures="$("$LIPO" -archs "$app/Contents/MacOS/$executable" 2>/dev/null || true)"
    for required in arm64 x86_64; do
        case " $architectures " in
            *" $required "*) pass "contains $required" ;;
            *) fail "missing architecture $required (found: ${architectures:-none})" ;;
        esac
    done
fi

# Nothing private ships inside the bundle.
secrets="$(find "$app" \( -iname '*.p12' -o -iname '*.p8' -o -iname '*.cer' \
    -o -iname '*.mobileprovision' -o -iname '*.keychain*' \) 2>/dev/null || true)"
if [ -n "$secrets" ]; then
    fail "the bundle carries signing material:"
    echo "$secrets" >&2
else
    pass "no signing material inside the bundle"
fi

fixtures="$(find "$app" -iname '*fixture*' 2>/dev/null || true)"
if [ -n "$fixtures" ]; then
    fail "the bundle carries test fixture resources:"
    echo "$fixtures" >&2
else
    pass "no fixture resources inside the bundle"
fi

if [ "$mode" = "signed" ]; then
    authorities="$("$CODESIGN" --verify --deep --strict --verbose=2 "$app" 2>&1)" || {
        fail "codesign --verify failed:"
        echo "$authorities" >&2
        authorities=""
    }
    if printf '%s' "$authorities" | grep -q 'Authority=Developer ID Application'; then
        pass "signed by a Developer ID Application authority"
    else
        fail "no Developer ID Application authority. Ad-hoc signing is not a distribution signature."
    fi
fi

if [ "$failures" -ne 0 ]; then
    echo "verify-artifact: $failures check(s) refused this artifact" >&2
    exit 1
fi
echo "verify-artifact: $mode checks passed"
