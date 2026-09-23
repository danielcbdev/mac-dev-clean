# Verification — plan 06, Large Files

- **Date:** 2026-09-21
- **Branch:** `feat/large-files`
- **Toolchain:** Xcode 27.0 (27A266a); Apple Swift 6.4; macOS 27.0 (26A428); arm64

## Gate result

```text
$ MACDEVCLEAN_SKIP_UI_TESTS=1 bash scripts/verify.sh
exit status: 0
==> verify.sh: all checks that ran passed — UI tests NOT RUN
```

| Check | Result |
|---|---|
| `swift test --package-path Packages/MacDevCleanCore` | **Pass** — 211 tests, 0 failures |
| App unit tests, Debug | **Pass** — 31 tests, 0 failures |
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
| `MacDevCleanAppTests` | 31 | 0 |
| **Total run** | **242** | **0** |
| `MacDevCleanUITests` | 13 | **not run** |

The UI gate is blocked for the reason recorded in
[05-interface.md](05-interface.md): the application launches under XCUITest with
no window visible to the accessibility interface, and the committed plan 04
baseline fails identically. Three Large Files UI tests are written and compile;
they have not run and are not claimed to pass.

## Exit-gate checks

**No implicit home scan.** `testBroadRootsAreRefused` asserts `/`, `/System`,
`/Users`, `/Library`, `/Applications` and the user's own home directory are all
refused as Large Files roots, while a specific subfolder is accepted. The
interface states this too, rather than silently returning nothing.

**Only folders the user chose for this feature.**
`testAFolderThatWasNotChosenIsNeverScanned` passes two folders in the request
but places only one in `largeFileRoots`, and asserts the other is not walked.
Project roots grant no Large Files scope: the scanner filters the request
against `SafetyContext.largeFileRoots` before it starts.

**Nothing is selected by default.**
`testEveryCandidateIsHighRiskAndNoneIsPreselected` asserts every candidate is
`.high` risk in the `.largeFiles` category, and the model test
`testAScanSelectsNothing` asserts the selection is empty after results arrive.
There is deliberately **no "select all"** control in this feature.

**The threshold is inclusive at the boundary.**
`testThresholdIncludesBoundaryWithoutLeavingSelectedRoot` — a 100-byte file at a
100-byte threshold is included, 99 bytes is not, and a file in a sibling folder
is never seen.

**No threshold is measured by downloading a cloud file.**
`testACloudPlaceholderIsSkippedAndReported` asserts a placeholder produces no
row and an explicit `issue.cloudPlaceholderSkipped`.

**Symbolic links are informational only.**
`testASymlinkIsInformationalAndNotSelectable` asserts the row exists, reports
the size of the *link* rather than its target, and has `canSelect == false`.
`testOnlySelectableRowsBecomeCandidates` asserts no candidate is created for it,
so there is no route by which a link could reach the executor.

**Packages are documents, not folders.**
`testAPackageIsOneDocumentRatherThanAFolderToWalkInto` asserts the scanner does
not descend into a `.app`.

**Volume boundaries hold.** `testAnotherVolumeIsNotFollowed` uses a stub device
number, because mounting a real volume is not something a test may do to the
user's machine.

**Exclusions and overlapping folders.** `testAnExclusionRemovesARow` and
`testOverlappingChosenFoldersDoNotListAFileTwice`.

**Cancellation.** `testCancellingStopsTheScan` asserts a cancelled scan produces
no snapshot.

**The common cleanup protections are intact.**
`testACandidateWhoseFolderIsNoLongerChosenIsRejected` scans a folder, removes it
from the Large Files scope, and asserts the path policy then refuses the
candidate with `outsideScope`. There is no public API anywhere that trashes an
arbitrary URL: `manual.largeFile` is accepted only for a path inside a currently
chosen folder, with snapshot provenance, and the validated-plan types remain
unconstructible outside the `Cleanup` target.

**Sorting never changes the selection, and is stable.**
`testSortingIsStableAndNeverChangesTheSelection` uses two rows with identical
size and date and asserts the normalized path breaks the tie the same way every
time.

**Changing the threshold invalidates the results.**
`testChangingTheThresholdClearsResultsAndSelection` — results gathered under a
different question are discarded rather than quietly reused.

**Cancelling the folder picker changes nothing.**
`testCancellingThePickerPreservesPreviousResults` and
`testNothingIsScannedUntilTheUserChoosesFolders`.

## One import beyond the contract's table

`Scanning` now imports `UniformTypeIdentifiers` to name a file's kind. It is an
Apple framework, so the no-third-party-runtime-dependency rule is not engaged
and no architectural decision record is required. The kind is derived from the
file name only — the file is never opened to determine it.

## Known omissions and limitations

- **UI tests have not run**, including the three written for this feature.
- **The native folder picker has not been exercised.** Automation uses an
  injected fake; `NSOpenPanel` cancellation and multi-selection still need
  manual verification.
- **Read-only external volumes are refused by the ordinary path policy** rather
  than shown with a dedicated "cross-volume cleanup unsupported" status. The
  refusal is correct; the explanatory status is not implemented.
- **No independent review took place.**
