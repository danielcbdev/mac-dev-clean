# Verification — plan 01, foundation

All results below were produced by running the commands on the development
machine. Nothing here is estimated or carried over from another run.

- **Date:** 2026-09-21
- **Branch:** `feat/project-foundation`
- **Toolchain:** Xcode 27.0 (27A266a); Apple Swift 6.4
  (swiftlang-6.4.0.34.1 clang-2100.3.34.1); macOS 27.0 (26A428); arm64
- **Formatter:** `swift-format` from that toolchain, at
  `/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift-format`

## Gate result

```text
$ bash scripts/verify.sh
==> Toolchain
==> Swift package tests
==> App tests (Debug, ad-hoc signed so the UI test runner can launch)
==> Release build (unsigned)
==> Lint
==> Whitespace
==> verify.sh: all checks passed

exit status: 0
```

| Check | Command | Result |
|---|---|---|
| Package tests | `swift test --package-path Packages/MacDevCleanCore` | **Pass** — 7 tests, 0 failures |
| App tests, Debug | `xcodebuild ... -destination 'platform=macOS' test` | **Pass** — `** TEST SUCCEEDED **` |
| Release build | `xcodebuild ... -configuration Release build CODE_SIGNING_ALLOWED=NO` | **Pass** — `** BUILD SUCCEEDED **` |
| Lint | `bash scripts/lint.sh` | **Pass** — `lint: no findings` |
| Whitespace | `git diff --check` | **Pass** — no output |
| Remote CI | GitHub Actions `verify` job | **Not run** — see below |

## Test counts, as reported by the runners

| Suite | Tests | Failures | Elapsed |
|---|---:|---:|---|
| `DomainTests` (`DefaultsTests`) | 1 | 0 | 0.001 s |
| `TestSupportTests` (`FixtureTreeTests`) | 6 | 0 | 0.031 s |
| `MacDevCleanAppTests` (`LaunchTests`) | 3 | 0 | 0.008 s |
| `MacDevCleanUITests` (`LaunchUITests`) | 1 | 0 | 4.811 s |
| **Total** | **11** | **0** | |

No test is skipped and none has an empty assertion body.

## Exit-gate checks

**Desktop window launches.** `LaunchUITests.testDesktopWindowLaunches` launches
the built application with `--ui-testing` and waits for the accessibility
identifier `app.title`. It passed in 4.811 s, so the window was really created
and the element really found.

**Opening the app does not depend on a terminal `PATH`.** The UI test launches
the `.app` bundle through `XCUIApplication`, the same way Finder does, not
through a shell.

**Debug tests and Release build both pass.** Recorded above. The Release
configuration compiles without any test-support or fixture type, so DEBUG-only
fixtures cannot leak into a shipping binary.

**`Domain` imports Foundation only.**

```text
$ grep -rh "^import" Packages/MacDevCleanCore/Sources/Domain/ | sort -u
import Foundation
```

The other core targets currently declare no imports at all, since only their
module documentation exists so far.

**No real scan or deletion is invoked.** No production source outside the Trash
port even mentions `removeItem`, `rmdir` or `rm`:

```text
$ grep -rn "removeItem|rmdir|rm " <core production targets> MacDevCleanApp/App
Domain/SideEffectPorts.swift:6:  ... Production code never calls `rm`, `rmdir` or
Domain/SideEffectPorts.swift:7:  `removeItem` for user-selected cleanup ...
```

Both hits are the documentation comment stating the prohibition. `FixtureTree`
in `TestSupport` does call `removeItem`, deliberately and only on the unique
temporary directory it created itself, guarded by an ownership check.

**Automatic scanning stays off on first run.** `DefaultsTests` asserts
`scanOnLaunch == false`, threshold 1 GB, language `.system`, retention
`.forever`.

**Fixtures reject traversal paths.**
`FixtureTreeTests.testRejectsParentTraversalAndWritesNothingOutsideItsRoot`
asserts `file("../escape", bytes: 1)` throws `.invalidRelativePath` *and* that
no file appeared beside the fixture root. A companion test rejects absolute
paths for both `file` and `directory`.

## Gate-failure proof

Plan 01 Task 3 requires demonstrating that the gate can actually fail. The
default for `scanOnLaunch` was temporarily flipped to `true`:

```text
$ swift test --package-path Packages/MacDevCleanCore --filter DefaultsTests
.../DefaultsTests.swift:7: error: -[DomainTests.DefaultsTests
testNoAutomaticScanOrDeletion] : XCTAssertFalse failed
Test Case '-[DomainTests.DefaultsTests testNoAutomaticScanOrDeletion]' failed
Executed 1 test, with 1 failure (0 unexpected)
```

The default was then restored with a normal edit, and `git diff` against the
committed file came back empty, confirming the defect was not committed. The
full gate was re-run afterwards and passed.

## Known omissions and limitations

- **Remote CI has never executed.** A remote named `origin` existed before this
  work began, but no push is authorized, so `.github/workflows/ci.yml` has not
  run on a GitHub runner. It is checked in and its YAML parses, and that is the
  entire claim.
- **CI pins a toolchain that was never exercised.** Local validation used Xcode
  27.0. CI pins Xcode 26.6 on `macos-26`, because the only hosted image with
  Xcode 27 is a public preview. The workflow fails loudly if that Xcode is
  missing, but the 26.6 combination is untested until CI actually runs. Recorded
  in `docs/adr/0002-toolchain.md`.
- **The documented test command needed a correction.** The execution guide's
  `CODE_SIGNING_ALLOWED=NO` on the Debug test action kills the XCUITest runner
  before it connects on Apple Silicon. `scripts/verify.sh` runs that action with
  ad-hoc signing instead. Rationale and the observed error are in ADR 0002.
- **No independent review took place.** Self-review of the full branch diff was
  performed; nobody else reviewed this work.
- **No signing, notarization, DMG, cask or release artifact exists yet.** Those
  belong to plan 09.
