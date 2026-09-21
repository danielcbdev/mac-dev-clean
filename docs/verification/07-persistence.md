# Verification — plan 07, persistence, history and exclusions

- **Date:** 2026-09-21
- **Branch:** `feat/history-and-exclusions`
- **Toolchain:** Xcode 27.0 (27A266a); Apple Swift 6.4; macOS 27.0 (26A428); arm64

## Gate result

```text
$ MACDEVCLEAN_SKIP_UI_TESTS=1 bash scripts/verify.sh
exit status: 0
==> verify.sh: all checks that ran passed — UI tests NOT RUN
```

| Check | Result |
|---|---|
| `swift test --package-path Packages/MacDevCleanCore` | **Pass** — 230 tests, 0 failures |
| App unit tests, Debug | **Pass** — 41 tests, 0 failures |
| **UI tests** | **NOT RUN** — the XCUITest gate is still unavailable on this machine |
| Release build, unsigned | **Pass** |
| `bash scripts/check-token-access.sh` | **Pass** |
| `bash scripts/lint.sh` | **Pass** |
| `git diff --check` | **Pass** |
| Remote CI | **Not run** — no push authorized |

| Suite | Tests | Failures |
|---|---:|---:|
| `DomainTests` | 1 | 0 |
| `TestSupportTests` | 6 | 0 |
| `CleanupRulesTests` | 21 | 0 |
| `CleanupTests` | 39 | 0 |
| `ScanningTests` | 68 | 0 |
| `DockerIntegrationTests` | 76 | 0 |
| `PersistenceTests` | 19 | 0 |
| `MacDevCleanAppTests` | 41 | 0 |
| **Total run** | **271** | **0** |
| `MacDevCleanUITests` | 17 | **not run** |

The UI gate is blocked for the reason recorded in
[05-interface.md](05-interface.md). Four new UI tests are written and compile;
they have not run and are not claimed to pass.

## This milestone unlocks real cleanup

Until now `cleanupEnabled` was false and the interface said so. It is now set
from whether durable storage opened:

```swift
cleanupEnabled: durable != nil
```

`testDurableStorageIsWhatEnablesCleanup` asserts `SwiftDataRepositories`
reports `isDurable == true` and `SessionRepositories` reports `false`, so
in-memory storage can never be mistaken for the real thing.

## Exit-gate checks

**A relaunch preserves settings and history.**
`testSettingsSurviveAFreshContainerOnTheSameFile` writes preferences, roots and
three kinds of exclusion, discards the container entirely, opens a new one over
the same file and asserts everything is there.
`testOutcomesAndSummarySurviveAReopen` does the same for a completed session,
including a **negative** observed free-space delta, stored as measured.
`testSettingsSurviveARelaunchThroughTheSameStore` asserts the same through the
`SettingsModel` the interface actually uses.

**Interrupted sessions remain uncertain.**
`testAnInterruptedSessionBecomesIndeterminateAndIsNeverRemoved` begins a session,
abandons it, reopens the store and asserts the record is `indeterminate` with
`session.interrupted` — explicitly asserting it is *neither* `movedToTrash` nor
`failed`. `testAnInterruptedSessionIsShownAsUnknownRatherThanFailed` asserts the
interface counts it as unknown rather than as a problem, and offers no retry.

**Corrupt storage does not vanish.**
`testACorruptStoreFailsToOpenAndIsNotDestroyed` writes garbage to the store
path, asserts opening throws `storeUnavailable`, and then asserts the file is
**byte-for-byte what it was**. Recreating it would destroy the record of
everything the app had already done.

`testAnUnreadableRecordDoesNotHideTheRestOfTheSession` asserts one undecodable
row appears as an unreadable entry beside the good ones rather than taking the
session down with it.

**Exclusion edits immediately revoke stale authority.**
`testAChangedScopeInvalidatesRegisteredSnapshots` registers a snapshot, calls
`invalidateAfterSettingsChange()`, and asserts the policy revision increased and
the snapshot is gone — a later lookup throws `staleScan`. A cleanup already
running re-reads the context before each item, so it sees the new revision too.

**A failed save is not reported as success.**
`testAnExclusionThatCannotBeSavedIsNotReportedAsActive` uses a repository that
refuses every write and asserts the exclusion list is unchanged and an error
code is surfaced.

**History actions cannot delete user files.**
`testClearingHistoryNeverTouchesTheTrash` asserts clearing removes records while
the workspace spy sees no reveal and no Trash open.
`testClearingHistoryLeavesPreferencesRootsAndExclusionsAlone` asserts the other
three stores are untouched.

**"Show in Trash" only when it resolves.**
`testShowInTrashIsOfferedOnlyWhenTheLocationStillResolves` — Trash names change
and items get emptied, so the recorded location is checked before the action is
offered.

**Retention deletes records, never files.**
`testRetentionKeepsASessionExactlyAtTheBoundary` pins the 30-day boundary as
inclusive; `testAnUnfinishedSessionIsKeptHoweverOldItIs` asserts a session whose
outcome nobody knows is never quietly discarded; `testForeverRemovesNothing`.

**Beginning a session twice is refused.**
`testBeginningTheSameSessionTwiceIsRefused` — allowing it would reset progress
already recorded.

**Missing exclusion paths stay listed.**
`testAMissingExclusionPathStaysListedAsUnavailable` — a decision the user made
is not discarded because the folder is currently absent.

**Scan-on-launch stays off and needs roots.**
`testScanOnLaunchCannotBeEnabledWithoutRoots`.

**Settings store semantic values, not translated strings.**
`testPreferencesRoundTrip` round-trips `portugueseBrazil`, and
`testAPathExclusionKeepsItsExactCase` asserts a path exclusion is not folded to
lower case — a case-sensitive volume would treat a folded path as a different
place.

**History never stores file contents.** `testHistoryNeverStoresFileContents`.

**The store lives where it should.**
`testTheStoreLivesInApplicationSupportUnderTheAppName`.

## Known omissions and limitations

- **UI tests have not run**, including the four written for these screens.
- **Migration has never been exercised**, because there is only one schema
  version. The empty `stages` list is a statement that no schema change has
  happened, not an assertion that migration works.
- **The offline smoke test is implicit rather than explicit.** No target
  imports a networking API and nothing in the suite touches the network, but
  there is no test that asserts the absence.
- **A relaunch of the real application has not been observed**, because that
  requires the UI gate. Durability is proven at the repository and model level,
  across genuinely separate containers over the same file.
- **No independent review took place.**
