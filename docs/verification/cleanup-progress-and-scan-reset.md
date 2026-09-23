# Cleanup progress and scan reset

Evidence for the two overview/review adjustments requested on 2026-09-23:
progress while items move to the Trash, and dropping the scan after a cleanup
that moved or removed something.

Nothing here is a summary of what should have happened. Every command, exit
status and count below was produced on this machine on the date given, or is
recorded as not run.

## Toolchain

Both commands below printed:

```
Xcode 27.0
Build version 27A266a
swift-driver version: 1.168.6 Apple Swift version 6.4 (swiftlang-6.4.0.34.1 clang-2100.3.34.1)
Target: arm64-apple-macosx27.0.0
```

Date: 2026-09-23.

## Command 1 — full gate

```
$ bash scripts/verify.sh
```

Exit status: **65**.

| Check | Result |
|---|---|
| Swift package tests | passed. 232 XCTest cases, 0 failures (TestSupport 6, Scanning 70, Persistence 19, Domain 1, DockerIntegration 76, Cleanup 39, CleanupRules 21). Seven Swift Testing runs reported 0 tests |
| App unit tests | passed. 89 cases, 0 failures |
| UI tests | **failed**. 24 cases executed, 24 failed |
| Release build, token access, localization, release contracts, policy, lint, whitespace | **not run**. `set -e` stopped the script at the UI tests |

The UI failures are the existing XCUITest launch blocker. `scan.start` and
`sidebar.overview` never appeared to the accessibility interface, including
in `OnboardingUITests`, which this change does not touch. This is a failed
gate, not a pass.

## Command 2 — remaining checks, UI suite skipped

```
$ MACDEVCLEAN_SKIP_UI_TESTS=1 bash scripts/verify.sh
```

Exit status: **0**. The script itself printed
`verify.sh: all checks that ran passed — UI tests NOT RUN`.

| Check | Result |
|---|---|
| Swift package tests | passed (same 232 cases, 0 failures) |
| App unit tests | passed. 89 cases, 0 failures |
| UI tests | **not run**. `MACDEVCLEAN_SKIP_UI_TESTS=1` was set. Missing gate, not a pass |
| Release build (unsigned) | `** BUILD SUCCEEDED **` |
| Cleanup authority boundary | passed |
| Localization catalog | `Localization catalog valid: 255 keys` |
| Release script contracts | passed |
| Static cleanup and privacy policy | passed |
| Lint | `swift-format lint --strict` passed |
| Whitespace | `git diff --check` passed |

## What the tests cover

The 6 new app unit tests, all among the 89:

- `ReviewModelTests.testCleanupProgressFollowsItemsAsTheyAreReported` — the
  plan total is 2 and `results.count` is 1 while the fake Trash is held after
  the first item, then 2 when the run finishes.
- `ScanModelTests.testInvalidateClearsTheSnapshotTheCompletedFlagAndTheSelection`.
- `RootCoordinatorCleanupTests` — a successful cleanup and a partial cleanup
  (one item moved, one failed) leave `hasScanned == false` and `state == .idle`.
  Closing the review without confirming, and a cleanup where every item fails,
  leave the snapshot in place.
