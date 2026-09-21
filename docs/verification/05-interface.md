# Verification — plan 05, desktop interface

- **Date:** 2026-09-21
- **Branch:** `feat/app-shell`
- **Toolchain:** Xcode 27.0 (27A266a); Apple Swift 6.4; macOS 27.0 (26A428); arm64

## Gate result

```text
$ MACDEVCLEAN_SKIP_UI_TESTS=1 bash scripts/verify.sh
exit status: 0
==> verify.sh: all checks that ran passed — UI tests NOT RUN
```

| Check | Result |
|---|---|
| `swift test --package-path Packages/MacDevCleanCore` | **Pass** — 198 tests, 0 failures |
| App unit tests, Debug | **Pass** — 24 tests, 0 failures |
| **UI tests** | **NOT RUN** — see below. This is a missing gate, not a pass. |
| Release build, unsigned | **Pass** — `** BUILD SUCCEEDED **` |
| `bash scripts/check-token-access.sh` | **Pass** |
| `bash scripts/lint.sh` | **Pass** — `lint: no findings` |
| `git diff --check` | **Pass** |
| Remote CI | **Not run** — no push authorized |

| Suite | Tests | Failures |
|---|---:|---:|
| `DomainTests` | 1 | 0 |
| `TestSupportTests` | 6 | 0 |
| `CleanupRulesTests` | 21 | 0 |
| `CleanupTests` | 39 | 0 |
| `ScanningTests` | 55 | 0 |
| `DockerIntegrationTests` | 76 | 0 |
| `MacDevCleanAppTests` | 24 | 0 |
| **Total run** | **222** | **0** |
| `MacDevCleanUITests` | 10 | **not run** |

## The UI test gate is unavailable on this machine

**Ten UI tests are written, compile, and did not run.** They are not reported as
passing, and `scripts/verify.sh` refuses to call them passed: skipping requires
setting `MACDEVCLEAN_SKIP_UI_TESTS=1`, which prints "MISSING GATE" and changes
the final line of the gate.

### What happens

The application launches under XCUITest — the process exists, it owns the menu
bar — but it exposes **no window and no application menus** to the accessibility
interface, and the application element reports as `Disabled`. Every element
query therefore fails.

```text
Attributes: Application, pid: …, title: 'MacDevClean', Disabled
Element subtree:
 →Application, pid: …, title: 'MacDevClean', Disabled
    MenuBar, {{0.0, 0.0}, {1470.0, 33.0}}
      MenuBarItem, title: 'Apple'
```

### Why this is not a defect in this milestone's code

Three independent observations:

1. **The same tests passed earlier today**, on this machine, in the plan 04 gate
   run — the UI suite ran and passed as part of `verify.sh` before this
   milestone's work began.
2. **The committed baseline fails identically now.** The plan 05 work was
   stashed with `git stash push -u`, putting the tree at commit `9f05b6e`
   (`merge: integrate Docker support`), and `LaunchUITests` — unchanged since
   plan 01 — failed in exactly the same way. The work was then restored.
3. **The application itself works.** Launched normally it creates a proper
   window and writes its frame to preferences:

   ```text
   "NSWindow Frame SwiftUI.WindowGroup<…MacDevClean.ContentView…>-1-AppWindow-1"
       = "95 74 1280 840 0 0 1470 923"
   "NSSplitView Subview Frames …, SidebarNavigationSplitView" = (
       "0.000000, 0.000000, 220.000000, 911.000000, NO, NO",
       "220.000000, 0.000000, 1060.000000, 911.000000, NO, NO"
   )
   ```

   That is the specified geometry: a 1280×840 window with a 220 pt sidebar.

### What was ruled out

Ad-hoc signing (the runner is signed, and hardened runtime is off —
`flags=0x2(adhoc)`), a stale build (a full `clean build` changed nothing),
saved window state (none existed), a lingering instance (none), display sleep
(the display was woken and re-tested), the `TestSupport` link on the unit test
target (removed and re-tested), and Xcode's debug-dylib indirection
(`ENABLE_DEBUG_DYLIB = NO` changed nothing; the experiment was reverted).

### What is needed

An interactive macOS session where an application launched by XCUITest can
become active and be inspected through the accessibility interface. A macOS
permission prompt appeared on screen during this investigation; approving or
dismissing whatever is pending, and re-running, is the next step. **Until these
tests actually run, nothing in this document claims the interface behaves
correctly at runtime beyond what the 24 model tests cover.**

## What the model tests do cover

These ran and passed, and they carry most of the behavioural weight.

**A scan selects nothing.** `testNothingIsSelectedByAScan`.

**A cancelled run cannot overwrite a newer one.**
`testACancelledRunCannotOverwriteANewerOne` holds the first scan mid-stream with
a gated replay service, cancels it, runs a second scan to completion, then
releases the first and asserts it changed nothing. There is no sleep standing in
for a result.

**Revisiting a screen cannot start a second scan.**
`testASecondStartWhileScanningIsIgnored` asserts the underlying service was
entered exactly once.

**Docker's absence costs nothing else.**
`testDockerUnavailableLeavesFilesystemResultsIntact`.

**Filtering never changes the selection.**
`testFilteringDoesNotChangeTheSelection` selects two items, filters to one
ecosystem, and asserts both remain selected.

**Bulk selection never reaches high risk.**
`testHighRiskItemsAreNotSelectableFromTheList`.

**Docker bytes are never added to the filesystem total.**
`testDockerBytesAreNeverAddedToTheFilesystemTotal`; unknown sizes are counted
separately and sort last rather than being treated as zero.

**Acknowledgments lapse when the content changes.**
`testChangingTheSelectionResetsBothAcknowledgments`, with
`testTheSameContentDoesNotResetAnAcknowledgment` as the control.

**A double confirm schedules one cleanup.**
`testASecondConfirmWhileRunningDoesNothing` holds the executor mid-run with a
release gate, fires a second confirm, and asserts exactly one move was
requested.

**A refusal always settles the model and explains itself.**
`testAHighRiskItemWithoutConsentIsRefusedAndNothingIsRemoved` asserts zero Trash
calls, a `consentRequired` code, per-item issues, and `isRunning == false`.

**An expired plan reports a reason instead of acting.**
`testAnExpiredPlanReportsAReasonInsteadOfActing`.

**Outcomes are grouped and the diagnostic report stays private.**
`testAConfirmedCleanupReportsItsOutcomesGroupedByResult` and
`testTheDiagnosticReportCarriesNoPathsOrResourceNames`.

These run against the **real** validator and executor from the `Cleanup` target,
with only the Trash, Docker and the journal faked.

## Composition

`AppDependencies.live()` builds the real scanner, path policy, rule catalog,
registry, validator and executor. `PreviewDependencies.swift` is wrapped
entirely in `#if DEBUG`, so the Release build contains no fixture type and
rejects the launch arguments that would reach one. The application target does
not link the package's `TestSupport`; only the XCTest targets do.

The fixture composition creates a temporary tree of **real** artifacts and runs
the **real** scanner over it, so UI automation exercises the genuine pipeline
rather than a stub. Its `HOME` points at that temporary tree, so a fixture launch
never proposes the user's own folders or reads their real caches.

## Cleanup is deliberately disabled in the release composition

`SessionRepositories` keeps settings and history in memory and reports
`isDurable == false`. `AppDependencies.live()` passes that straight through to
`cleanupEnabled`, so the release build scans and explains but the cleanup action
reports itself unavailable, with a card saying why. A cleanup whose record
disappears when the app quits is not something to offer. Plan 07 replaces this
with SwiftData.

## Known omissions and limitations

- **UI tests have not run.** Stated above, and not softened.
- **No screenshots** have been captured. The UI test that captures them exists
  but has not run, and screen capture on this machine requires a permission the
  session does not have.
- **The native folder picker has not been exercised.** UI automation uses an
  injected fake, by design — `NSOpenPanel` cancellation and multi-selection need
  manual verification, which has not been performed.
- **Dark mode, Increase Contrast, Reduce Transparency and large text sizes have
  not been inspected visually.** The layout uses `ViewThatFits`, semantic colours
  and no fixed text heights specifically to survive them, but that is a design
  intention, not an observation.
- **Large Files, History, Exclusions and Settings are placeholders** that say so.
- **No independent review took place.** Self-review of the full branch diff was
  performed; nobody else reviewed this work.
