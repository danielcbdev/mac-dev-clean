#!/bin/bash
#
# Contract tests for the release scripts.
#
# No real build runs here, and nothing is signed. Every external tool is a
# fixture executable passed in by an explicit environment variable, never by
# putting a directory in front of the real PATH — spoofing the developer's PATH
# would leak into anything else the session runs.
#
# Everything these tests create lives under one mktemp -d directory that this
# runner owns and removes. They never write outside it.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

fixture_root="$(mktemp -d)"
case "$fixture_root" in
    /*/*) ;;
    *)
        echo "Refusing to run with an implausible fixture root: $fixture_root" >&2
        exit 1
        ;;
esac
cleanup() {
    [ -d "$fixture_root" ] && rm -rf "$fixture_root"
}
trap cleanup EXIT

failures=0

check() {
    local description="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        echo "  ok: $description"
    else
        echo "  FAILED: $description" >&2
        failures=$((failures + 1))
    fi
}

refute() {
    local description="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        echo "  FAILED: $description" >&2
        failures=$((failures + 1))
    else
        echo "  ok: $description"
    fi
}

# --- fixture tools -----------------------------------------------------------

bin="$fixture_root/bin"
mkdir -p "$bin"

# A build that succeeds: writes a minimal app bundle where the real xcodebuild
# would put one, so the caller's own staging logic is what gets exercised.
cat > "$bin/xcodebuild-success" <<'FAKE'
#!/bin/bash
set -euo pipefail
derived=""
previous=""
for argument in "$@"; do
    [ "$previous" = "-derivedDataPath" ] && derived="$argument"
    previous="$argument"
done
[ -n "$derived" ] || { echo "fake xcodebuild: no -derivedDataPath" >&2; exit 1; }
app="$derived/Build/Products/Release/MacDevClean.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
printf 'fake binary' > "$app/Contents/MacOS/MacDevClean"
chmod +x "$app/Contents/MacOS/MacDevClean"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>MacDevClean</string>
  <key>CFBundleIdentifier</key><string>dev.macdevclean.app</string>
  <key>CFBundleName</key><string>MacDevClean</string>
  <key>CFBundleShortVersionString</key><string>1.0.0</string>
  <key>CFBundleIconName</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
</dict>
</plist>
PLIST
echo "** BUILD SUCCEEDED **"
FAKE

cat > "$bin/xcodebuild-failure" <<'FAKE'
#!/bin/bash
echo "** BUILD FAILED **" >&2
exit 65
FAKE

# hdiutil stand-in: asserts the staging layout it was handed, and produces a
# file where the real one would produce a disk image.
cat > "$bin/hdiutil-success" <<'FAKE'
#!/bin/bash
set -euo pipefail
output="${!#}"
source_folder=""
previous=""
for argument in "$@"; do
    [ "$previous" = "-srcfolder" ] && source_folder="$argument"
    previous="$argument"
done
[ -d "$source_folder" ] || { echo "fake hdiutil: no -srcfolder" >&2; exit 1; }
[ -e "$source_folder/MacDevClean.app" ] || { echo "fake hdiutil: no app staged" >&2; exit 1; }
[ -L "$source_folder/Applications" ] || { echo "fake hdiutil: no Applications link" >&2; exit 1; }
printf 'fake disk image' > "$output"
FAKE

cat > "$bin/lipo-universal" <<'FAKE'
#!/bin/bash
echo "x86_64 arm64"
FAKE

cat > "$bin/lipo-single" <<'FAKE'
#!/bin/bash
echo "arm64"
FAKE

# codesign stand-ins. The ad-hoc one is what an unsigned local build looks
# like; verify-artifact must never accept it as a Developer ID signature.
cat > "$bin/codesign-developer-id" <<'FAKE'
#!/bin/bash
cat >&2 <<'OUT'
Authority=Developer ID Application: Example Owner (ABCDE12345)
Authority=Developer ID Certification Authority
Authority=Apple Root CA
OUT
FAKE

cat > "$bin/codesign-adhoc" <<'FAKE'
#!/bin/bash
echo "Signature=adhoc" >&2
FAKE

cat > "$bin/codesign-unsigned" <<'FAKE'
#!/bin/bash
echo "code object is not signed at all" >&2
exit 1
FAKE

chmod +x "$bin"/*

# --- helpers -----------------------------------------------------------------

# Builds an app bundle by hand, so verify-artifact can be tested without a real
# build. Arguments: destination, minimum system version, version.
make_app() {
    local app="$1"
    local minimum="${2:-14.0}"
    local version="${3:-1.0.0}"
    mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
    printf 'fake binary' > "$app/Contents/MacOS/MacDevClean"
    chmod +x "$app/Contents/MacOS/MacDevClean"
    cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>MacDevClean</string>
  <key>CFBundleIdentifier</key><string>dev.macdevclean.app</string>
  <key>CFBundleName</key><string>MacDevClean</string>
  <key>CFBundleShortVersionString</key><string>$version</string>
  <key>CFBundleIconName</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>$minimum</string>
</dict>
</plist>
PLIST
}

# --- build-local -------------------------------------------------------------

echo "==> build-local.sh"

build_local() {
    # Derived data goes inside the fixture root too, so a fake build never
    # leaves an app where a real build would later look for one.
    MACDEVCLEAN_XCODEBUILD="$1" \
        MACDEVCLEAN_DERIVED_DATA="$fixture_root/derived" \
        bash "$root/scripts/build-local.sh" "${@:2}"
}

refute "a version that is not a semantic version is refused" \
    build_local "$bin/xcodebuild-success" \
    --version "1.0" --output "$fixture_root/refused"

refute "a version carrying a shell fragment is refused" \
    build_local "$bin/xcodebuild-success" \
    --version '1.0.0; touch /tmp/pwned' --output "$fixture_root/refused"

refute "a failing build does not produce an app" \
    build_local "$bin/xcodebuild-failure" \
    --version "1.0.0" --output "$fixture_root/failed-build"
refute "and leaves no app behind" test -e "$fixture_root/failed-build/MacDevClean.app"

spaced="$fixture_root/a path with spaces"
check "a build succeeds into a path containing spaces" \
    build_local "$bin/xcodebuild-success" --version "1.2.3" --output "$spaced"
check "the staged bundle has its executable" \
    test -x "$spaced/MacDevClean.app/Contents/MacOS/MacDevClean"
check "the staged bundle has its Info.plist" \
    test -f "$spaced/MacDevClean.app/Contents/Info.plist"

refute "an existing app in the output is not overwritten" \
    build_local "$bin/xcodebuild-success" --version "1.2.3" --output "$spaced"

# --- package-dmg -------------------------------------------------------------

echo "==> package-dmg.sh"

package_dmg() {
    MACDEVCLEAN_HDIUTIL="$1" bash "$root/scripts/package-dmg.sh" "${@:2}"
}

refute "a missing app is refused" \
    package_dmg "$bin/hdiutil-success" \
    --app "$fixture_root/missing.app" --output "$fixture_root/missing.dmg"

check "an app in a path with spaces packages" \
    package_dmg "$bin/hdiutil-success" \
    --app "$spaced/MacDevClean.app" --output "$fixture_root/out with spaces.dmg"
check "the image exists" test -f "$fixture_root/out with spaces.dmg"

refute "an existing output path is refused rather than overwritten" \
    package_dmg "$bin/hdiutil-success" \
    --app "$spaced/MacDevClean.app" --output "$fixture_root/out with spaces.dmg"
check "and the existing file is untouched" \
    grep -q "fake disk image" "$fixture_root/out with spaces.dmg"

# --- verify-artifact ---------------------------------------------------------

echo "==> verify-artifact.sh"

verify_artifact() {
    MACDEVCLEAN_LIPO="$1" MACDEVCLEAN_CODESIGN="$2" \
        bash "$root/scripts/verify-artifact.sh" "${@:3}"
}

good="$fixture_root/good/MacDevClean.app"
make_app "$good"

check "a universal unsigned app passes unsigned verification" \
    verify_artifact "$bin/lipo-universal" "$bin/codesign-unsigned" \
    --app "$good" --mode unsigned

single="$fixture_root/single/MacDevClean.app"
make_app "$single"
refute "a single-architecture app is refused" \
    verify_artifact "$bin/lipo-single" "$bin/codesign-unsigned" \
    --app "$single" --mode unsigned

wrong_minimum="$fixture_root/minimum/MacDevClean.app"
make_app "$wrong_minimum" "15.0"
refute "an app claiming the wrong minimum system version is refused" \
    verify_artifact "$bin/lipo-universal" "$bin/codesign-unsigned" \
    --app "$wrong_minimum" --mode unsigned

missing_executable="$fixture_root/broken/MacDevClean.app"
make_app "$missing_executable"
rm "$missing_executable/Contents/MacOS/MacDevClean"
refute "an app whose CFBundleExecutable does not resolve is refused" \
    verify_artifact "$bin/lipo-universal" "$bin/codesign-unsigned" \
    --app "$missing_executable" --mode unsigned

with_secret="$fixture_root/secret/MacDevClean.app"
make_app "$with_secret"
printf 'not a real certificate' > "$with_secret/Contents/Resources/signing.p12"
refute "an app carrying a signing file is refused" \
    verify_artifact "$bin/lipo-universal" "$bin/codesign-unsigned" \
    --app "$with_secret" --mode unsigned

with_fixture="$fixture_root/fixture/MacDevClean.app"
make_app "$with_fixture"
mkdir -p "$with_fixture/Contents/Resources/PreviewFixtureWorld"
refute "an app carrying preview fixture resources is refused" \
    verify_artifact "$bin/lipo-universal" "$bin/codesign-unsigned" \
    --app "$with_fixture" --mode unsigned

refute "ad-hoc signing is never accepted as a Developer ID signature" \
    verify_artifact "$bin/lipo-universal" "$bin/codesign-adhoc" \
    --app "$good" --mode signed

refute "an unsigned app fails signed verification" \
    verify_artifact "$bin/lipo-universal" "$bin/codesign-unsigned" \
    --app "$good" --mode signed

check "a Developer ID signature passes signed verification" \
    verify_artifact "$bin/lipo-universal" "$bin/codesign-developer-id" \
    --app "$good" --mode signed

# --- result ------------------------------------------------------------------

if [ "$failures" -ne 0 ]; then
    echo "release contract tests: $failures failed" >&2
    exit 1
fi
echo "release contract tests passed"
