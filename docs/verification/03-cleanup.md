# Verification — plan 03, cleanup safety

All results were produced by running the commands on the development machine.

- **Date:** 2026-09-21
- **Branch:** `feat/cleanup-safety`
- **Toolchain:** Xcode 27.0 (27A266a); Apple Swift 6.4; macOS 27.0 (26A428); arm64

## Gate result

```text
$ bash scripts/verify.sh
exit status: 0
```

| Check | Result |
|---|---|
| `swift test --package-path Packages/MacDevCleanCore` | **Pass** — 122 tests, 0 failures |
| App tests, Debug | **Pass** — `** TEST SUCCEEDED **` |
| Release build, unsigned | **Pass** — `** BUILD SUCCEEDED **` |
| `bash scripts/check-token-access.sh` | **Pass** — `the cleanup authority boundary holds` |
| `bash scripts/lint.sh` | **Pass** — `lint: no findings` |
| `git diff --check` | **Pass** — no output |
| Remote CI | **Not run** — no push authorized |

| Suite | Tests | Failures |
|---|---:|---:|
| `DomainTests` | 1 | 0 |
| `TestSupportTests` | 6 | 0 |
| `CleanupRulesTests` | 21 | 0 |
| `ScanningTests` | 55 | 0 |
| `CleanupTests` | 39 | 0 |
| `MacDevCleanAppTests` | 3 | 0 |
| `MacDevCleanUITests` | 1 | 0 |
| **Total** | **126** | **0** |

## Exit-gate checks

**Forged and stale selections fail.** `testUnregisteredSelectionIsRejected`
(unknown scan), `testAnUnknownCandidateInAKnownScanIsRejected`,
`testAnInvalidatedSnapshotCannotBeUsed`, `testAChangedPolicyRevisionMakesTheSelectionStale`,
`testAnExclusionAddedWhileReviewIsOpenInvalidatesTheSelection` and its category
counterpart. The exclusion tests deliberately leave the revision counter alone,
so they prove the exclusion itself is re-read rather than only the counter.

**Authority cannot be constructed outside `Cleanup`.**
`scripts/check-token-access.sh` type-checks
`CompileFailures/ForgedToken.swift.fixture` against the built modules and
requires it to fail *with an inaccessibility diagnostic* — any other compiler
error is treated as the check being broken rather than as a pass. A second
fixture, `PublicConsumer.swift.fixture`, must type-check, which proves the
public surface still works and that the first failure really is about access
control. The script runs inside `verify.sh`.

**No production `rm` / `removeItem` cleanup fallback.**

```text
$ grep -rn "removeItem|rmdir|unlink(" <core production targets> MacDevCleanApp
Domain/SideEffectPorts.swift:  ... Production code never calls `rm`, `rmdir` or
                                   `removeItem` for user-selected cleanup ...
```

The only hits are the documentation comment stating the prohibition.
`testAnUnavailableTrashFailsTheItemWithoutDeletingAnything` asserts the fixture
is still on disk after a Trash failure, so the absence is behavioural and not
just textual.

**Expired and reused plans cannot execute.** `testAnExpiredPlanCannotExecute`
advances a `MutableTestClock` by 61 seconds; `testConfirmingTwiceDoesNotActTwice`
asserts one Trash call across two confirmations, with the second run reporting
`usedPlan`.

**Known identity swaps are blocked.** `testReplacementAfterReviewIsNeverTrashed`
replaces the target with a different inode after validation and asserts zero
Trash calls. `testAnAncestorReplacedByASymlinkAfterReviewIsNeverTrashed` swaps
the *parent* for a symbolic link pointing elsewhere — the leaf still exists at
the end of the path — and asserts the swap is not followed. Both replacements
rename the original inside the harness's own temporary tree; nothing is ever
unlinked.

**Errors, cancellation and journal failure are tested.**
`testOneFailureDoesNotAbandonTheRestOfThePlan`,
`testCancellingStopsAfterTheItemInFlight`,
`testJournalFailureBeforeRemovalHasNoSideEffect`,
`testRecordFailureAfterASuccessStopsTheRunAndMarksItUnrecorded`,
`testRepeatingAfterAJournalFailureDoesNotRepeatTheSideEffect` and
`testPendingRowsBecomeIndeterminateOnRecovery`.

**Moving to the Trash is never reported as freed space.**
`testBytesMovedToTrashAreNotReportedAsBytesFreed` uses a stub volume reporting
identical free space before and after — which is what actually happens on the
same volume — and asserts 4096 bytes moved with a delta of 0.
`testANegativeFreeSpaceDeltaIsReportedAsMeasured` asserts a negative observation
survives unclamped. `testOnlyConfirmedMovesContributeBytes` asserts a failed
item's bytes are excluded.

**Diagnostics stay private.**
`testTheDiagnosticReportContainsNoPathsOrResourceNames` builds a report from a
session containing a real fixture path and a Docker volume named
`customer-database`, and asserts the report contains neither, nor the home
directory, nor any `file://` URL — while still containing the rule identifiers,
outcome counts and the reminder that bytes moved are not bytes freed.

**Synthetic targets only.** Every test in this milestone runs inside a
`FixtureTree` it created, with `RecordingTrash`, `RecordingDocker` and
`InMemoryJournal` standing in for the three things that would touch the machine.
No test reaches a real cache, the real Trash or a live Docker daemon.

## Deviations, stated plainly

- **Task 2 was not written test-first.** The harness the plan specifies wires
  both the validator *and* the executor, so neither could compile until both
  existed. Task 1 followed red/green properly (the validation suite was written
  first and observed failing). For Task 2 the executor was written before
  `ExecutionTests`, and the suite passed on its first run. Two of those tests
  were then deliberately tightened — the cancellation test now holds the
  executor with a release gate instead of racing it — but the initial failing
  state that red/green is meant to provide was not obtained, and that is a real
  gap in the discipline rather than a formality.
- **ADR numbering.** Plan 03 calls for `docs/adr/0003-trash-first.md`. That
  number was taken during plan 02, so the decision is recorded as
  `0004-trash-first.md`.
- **Two journal defects were found by these tests**, which is the point of
  writing them: recovery skipped sessions already marked complete even when they
  still held a pending row, and one assertion of mine was simply wrong (the word
  "Trash" legitimately appears in the report as a label). Both are fixed.

## Known omissions and limitations

- **The path race is not closed, and cannot be.** `trashItem` takes a path, not
  a descriptor. Identity and ancestor revalidation narrow the window; they do
  not eliminate it. Recorded in
  [docs/security/threat-model.md](../security/threat-model.md).
- **Persistence is still in memory.** `InMemoryJournal` fulfils
  `HistoryRepository` for now; durable SwiftData storage is plan 07. Production
  cleanup stays disabled in the app until that is composed.
- **Docker execution is faked.** `RecordingDocker` proves the executor's
  contract with a daemon; the real integration is plan 04. No test has contacted
  a Docker daemon.
- **No independent review took place.** Self-review of the full branch diff was
  performed; nobody else reviewed this work.
