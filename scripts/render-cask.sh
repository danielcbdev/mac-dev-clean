#!/bin/bash
#
# Renders the Homebrew cask for a release that actually exists.
#
# Do not run this with invented inputs. A cask whose url and sha256 do not
# describe a real published artifact is worse than no cask: it fails at
# install time, for everyone, after they trusted it.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUBY="${MACDEVCLEAN_RUBY:-/usr/bin/ruby}"

usage() {
    echo "usage: render-cask.sh --owner <owner> --repo <repo> --version <semver> \\" >&2
    echo "                      --sha256 <digest> --output <path>" >&2
}

owner=""
repo=""
version=""
sha256=""
output=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --owner) owner="${2:-}"; shift 2 ;;
        --repo) repo="${2:-}"; shift 2 ;;
        --version) version="${2:-}"; shift 2 ;;
        --sha256) sha256="${2:-}"; shift 2 ;;
        --output) output="${2:-}"; shift 2 ;;
        *) usage; exit 2 ;;
    esac
done

if [ -z "$owner" ] || [ -z "$repo" ] || [ -z "$version" ] || [ -z "$sha256" ] \
    || [ -z "$output" ]; then
    usage
    exit 2
fi

# Five literal arguments. The generator validates each one itself; nothing here
# is spliced into Ruby source.
"$RUBY" "$ROOT/scripts/render-cask.rb" "$owner" "$repo" "$version" "$sha256" "$output"
echo "==> Wrote $output"
