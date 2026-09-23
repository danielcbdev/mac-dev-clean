#!/bin/bash
#
# Reports whether a release can proceed, before anything is built or signed.
#
# --mode unsigned is the local development path and needs no credentials.
# --mode public requires every value a signed, notarized release depends on,
# and fails naming only the variables that are missing. It never prints a
# value, a length, or a prefix: a secret that leaks into a log is leaked.
set -euo pipefail

usage() {
    echo "usage: release-preflight.sh --mode unsigned|public" >&2
}

mode=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --mode) mode="${2:-}"; shift 2 ;;
        *) usage; exit 2 ;;
    esac
done

case "$mode" in
    unsigned|public) ;;
    *) usage; exit 2 ;;
esac

# Configuration, not secrets: the owner, repository and bundle identifier that
# a real release belongs to. They have no defaults, because a guessed owner
# would publish to the wrong place.
configuration=(
    MACDEVCLEAN_RELEASE_OWNER
    MACDEVCLEAN_RELEASE_REPO
    MACDEVCLEAN_BUNDLE_ID
)

secrets=(
    APPLE_TEAM_ID
    APPLE_CERTIFICATE_P12_BASE64
    APPLE_CERTIFICATE_PASSWORD
    APPLE_API_KEY_ID
    APPLE_API_ISSUER_ID
    APPLE_API_PRIVATE_KEY
)

if [ "$mode" = "unsigned" ]; then
    echo "preflight: unsigned build, no release configuration required"
    echo "preflight: the result is a development artifact, not a release"
    exit 0
fi

missing=()
for name in "${configuration[@]}" "${secrets[@]}"; do
    if [ -z "${!name:-}" ]; then
        missing+=("$name")
    fi
done

if [ "${#missing[@]}" -ne 0 ]; then
    echo "preflight: a public release cannot proceed. Missing:" >&2
    for name in "${missing[@]}"; do
        echo "  $name" >&2
    done
    echo "See docs/release/configuration.md. No value is printed here." >&2
    exit 1
fi

# Shape checks only, on values that are not secret.
if ! printf '%s' "${MACDEVCLEAN_RELEASE_OWNER}" | grep -qE '^[A-Za-z0-9][A-Za-z0-9-]*$'; then
    echo "preflight: MACDEVCLEAN_RELEASE_OWNER is not a valid GitHub owner" >&2
    exit 1
fi
if ! printf '%s' "${MACDEVCLEAN_RELEASE_REPO}" | grep -qE '^[A-Za-z0-9][A-Za-z0-9_.-]*$'; then
    echo "preflight: MACDEVCLEAN_RELEASE_REPO is not a valid repository name" >&2
    exit 1
fi
if ! printf '%s' "${MACDEVCLEAN_BUNDLE_ID}" | grep -qE '^[A-Za-z0-9][A-Za-z0-9.-]*$'; then
    echo "preflight: MACDEVCLEAN_BUNDLE_ID is not a reverse-DNS identifier" >&2
    exit 1
fi

echo "preflight: public release configuration is present"
