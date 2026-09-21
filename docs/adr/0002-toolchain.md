# ADR 0002: Pinned toolchain, ad-hoc signing and the CI toolchain gap

- **Status:** Accepted
- **Date:** 2026-09-21
- **Plan:** 01 foundation, Tasks 2 and 3

## Context

Swift 6 language mode needs Xcode 16 or newer. The implementation clarifications
require choosing one specific available Xcode build, recording it, and pinning
CI to that tested version — explicitly without pretending every Xcode 16+
release was tested.

## Decision: the toolchain this repository was validated against

These are the actual versions used to run the checks recorded in
`docs/verification/01-foundation.md`, captured on the development machine on
2026-09-21:

```text
$ xcodebuild -version
Xcode 27.0
Build version 27A266a

$ swift --version
swift-driver version: 1.168.6 Apple Swift version 6.4
(swiftlang-6.4.0.34.1 clang-2100.3.34.1)
Target: arm64-apple-macosx27.0.0

$ sw_vers
ProductName:    macOS
ProductVersion: 27.0
BuildVersion:   26A428
```

The formatter is the one bundled with that toolchain, resolved through
`xcrun --find swift-format`. Nothing is downloaded during a build or a lint run.

The package manifest uses `swift-tools-version: 6.0` and every target sets
`.swiftLanguageMode(.v6)` explicitly. Core targets stay nonisolated — that is
the Swift 6 default and no core target opts into a global actor. The app target
sets `SWIFT_DEFAULT_ACTOR_ISOLATION = nonisolated` so UI isolation is written
out with explicit `@MainActor` rather than inherited implicitly.

The deployment target is macOS 14.0, verified by a test that reads
`LSMinimumSystemVersion` from the built bundle.

## Decision: ad-hoc signing, and one correction to the documented test command

The project signs ad hoc — `CODE_SIGN_IDENTITY = "-"`, `CODE_SIGN_STYLE =
Manual`, empty `DEVELOPMENT_TEAM`, no provisioning profile. A fresh clone builds,
runs and tests with no Apple account.

The execution guide's baseline test command passes `CODE_SIGNING_ALLOWED=NO` to
the Debug test action. **That command cannot run the UI tests on Apple Silicon.**
Observed on this machine:

```text
MacDevCleanUITests-Runner encountered an error (Early unexpected exit, operation
never finished bootstrapping - no restart will be attempted. (Underlying Error:
Test crashed with signal kill before establishing connection.))
```

The XCUITest runner is a separate application. With signing disabled it is
produced unsigned, and the system kills it before it can connect to the test
host, so the UI test never starts and the gate reports a failure unrelated to
the code under test.

`scripts/verify.sh` therefore runs the Debug **test** action without
`CODE_SIGNING_ALLOWED=NO`, letting it sign ad hoc. The Release **build** keeps
`CODE_SIGNING_ALLOWED=NO`, because nothing is launched there. The behaviour the
guide intended — no account, no certificate, no secret — is preserved; only the
mechanism changed.

The regression guard is the gate itself: `scripts/verify.sh` runs the UI test on
every invocation, so a future change that breaks runner signing fails the gate
rather than silently skipping the test.

## Decision: what CI pins, and what has not been verified

CI runs on the `macos-26` hosted image and pins `/Applications/Xcode_26.6.app`
(Xcode 26.6, build 17F113), selected explicitly with `xcode-select`. If that
exact path is absent the job fails loudly and prints the installed Xcode
versions; it never falls back to whatever happens to be default.

The runner inventory was read from `actions/runner-images` on 2026-09-21. The
only image carrying Xcode 27 is `xcode-27-arm64`, announced as a **public
preview**, so it is not a stable label to pin a gate to. `macos-26` carries
Xcode 26.6 as its default and is the newest stable pair available.

**Stated plainly: CI has never run.** The repository has a remote, but no push
is authorized, so this workflow has not executed on a real runner, and the
combination of Xcode 26.6 with this code has not been tested anywhere. The
locally validated toolchain is Xcode 27.0 only. This gap closes the first time
an authorized push runs the workflow, and not before.

Action versions are pinned to immutable commit SHAs resolved from the GitHub API
on 2026-09-21: `actions/checkout` v7.0.1 at
`3d3c42e5aac5ba805825da76410c181273ba90b1` and `actions/upload-artifact` v7.0.1
at `043fb46d1a93c77aae656e7c1c64a875d1fc6a0a`.

## Consequences

Contributors need Xcode 16 or newer; this repository is known-good on 27.0.
Raising or lowering the pin means re-running the full gate and updating this
record with the real output, not editing the version string.
