# Verification — plan 02, scanning

All results were produced by running the commands on the development machine.
Nothing here is estimated.

- **Date:** 2026-09-21
- **Branch:** `feat/scanning-engine`
- **Toolchain:** Xcode 27.0 (27A266a); Apple Swift 6.4; macOS 27.0 (26A428); arm64

## Gate result

```text
$ bash scripts/verify.sh
exit status: 0
```

| Check | Result |
|---|---|
| `swift test --package-path Packages/MacDevCleanCore` | **Pass** — 83 tests, 0 failures |
| App tests, Debug (`xcodebuild ... test`) | **Pass** — `** TEST SUCCEEDED **` |
| Release build, unsigned | **Pass** — `** BUILD SUCCEEDED **` |
| `bash scripts/lint.sh` | **Pass** — `lint: no findings` |
| `git diff --check` | **Pass** — no output |
| Remote CI | **Not run** — no push authorized |

## Test counts, as reported by the runners

| Suite | Tests | Failures |
|---|---:|---:|
| `DomainTests` | 1 | 0 |
| `TestSupportTests` | 6 | 0 |
| `CleanupRulesTests` | 21 | 0 |
| `ScanningTests` | 55 | 0 |
| `MacDevCleanAppTests` | 3 | 0 |
| `MacDevCleanUITests` | 1 | 0 |
| **Total** | **87** | **0** |

## Exit-gate checks

**Supported fixture roots produce correct candidates.**
`testFindsAndMeasuresASupportedProjectArtifact` builds a project with a
`package.json` and a `node_modules` holding 1000 + 24 bytes, and asserts one
candidate of exactly 1024 bytes. Sibling tests pin the negative cases: a bare
`build` directory, `node_modules` without a manifest, an unparseable manifest, a
Dart-only `pubspec.yaml`, a `dist` that Git tracks, a `dist` with no declared
output, and a `dist` whose ignore status Git could not report.

**No traversal follows symlinks or mounts.**
`testASymbolicLinkInsideACandidateIsNotFollowed` puts 5000 bytes behind a link
inside the candidate and asserts the reported size stays 100.
`testASymbolicLinkAncestorCannotSmuggleATargetIntoScope` shows a link cannot
move a target into scope. `testATargetOnAnotherVolumeIsRejected` uses a stub
device number, because mounting a real volume is not something a test may do to
the user's machine.

**Unknown measurements remain unknown.**
`SizeAccumulatorTests.testAnUnknownSizeMakesTheTotalUnknownRatherThanWrong`
asserts the reported total becomes `nil` rather than silently omitting the
unmeasurable file. `testOverflowThrowsRatherThanWrappingAround` asserts
`addingReportingOverflow` throws and the accumulator keeps its last valid value.

**Hard links are counted once.** `testHardLinkBytesAreCountedOnce`, with
`testTheSameInodeOnAnotherVolumeIsADifferentFile` confirming the key is the
device *and* the inode.

**A permission failure in one subtree preserves the others.**
`testAnUnreadableSubtreePreservesTheOtherResults` makes one sibling directory
unreadable and asserts the good result survives *and* that
`issue.permissionDenied` is reported rather than swallowed.

**Cancellation stops enumeration, not just the interface.**
`testCancellingStopsEnumerationRatherThanOnlyHidingIt` runs against a synthetic
100,000-entry tree. The fake filesystem stops answering after 20 reads, so the
scan is provably mid-walk — the test asserts fewer than 100 reads at that point —
then the consumer leaves the loop. The test asserts no snapshot was produced,
releases the fake, waits on a bounded `XCTestExpectation` for the read count to
stabilise, and asserts enumeration did not resume. There is no fixed sleep
standing in for a result, and nothing depends on winning a race with the
producer.

**Overlapping roots are deduplicated.** `testOverlappingRootsDoNotProduceDuplicates`
passes a root and one of its own descendants and asserts a single candidate.
`testOnlyTheOutermostOverlappingCandidateIsOffered` asserts nested candidates
collapse to the outermost.

**An excluded descendant blocks its ancestor.**
`testAnExcludedDescendantSkipsItsAncestorInsteadOfTrashingIt` asserts the
ancestor is skipped entirely rather than being trashed with the excluded child
inside it.

**Rule evidence and the policy snapshot are registered for the validator.**
`testTheSnapshotIsRegisteredWithItsPolicyRevisionBeforeCompletion` asserts the
snapshot is in the store, with its policy revision, before `completed` is
announced. `testEachScanProducesANewSnapshotIdentity` asserts a rescan is a new
snapshot rather than a mutation of the old one.

## Corrections to the documented commands

The implementation clarifications specify `ls-files -z` and `check-ignore -z`
"with literal pathspecs". Two spellings do not work against the Git on the
tested toolchain. Both were corrected while preserving the intent, both are
pinned by tests, and the reasoning is recorded in
[ADR 0003](../adr/0003-git-evidence-adapter.md).

```text
$ git check-ignore -z -- dist
fatal: -z only makes sense with --stdin

$ GIT_LITERAL_PATHSPECS=1 git check-ignore -z --stdin
fatal: dist: pathspec magic not supported by this command: 'literal'
```

`ls-files` keeps literal pathspecs. `check-ignore` receives the path on standard
input and its answer is accepted only when the pathname Git echoes back matches
byte for byte.

## Known omissions and limitations

- **A `tsconfig.json` containing comments is not parsed**, so such a project's
  `dist` is never offered. This is deliberate — see
  [docs/cleanup-rules.md](../cleanup-rules.md) — and it means a real false
  negative for many TypeScript projects.
- **Only regular files contribute bytes.** Directory metadata is not counted, so
  the figure is an estimate of content. It is never presented as a prediction of
  reclaimed space.
- **No performance baseline is recorded yet.** The 100,000-entry fixture proves
  cancellation, not throughput. Measured performance belongs to plan 08.
- **Docker candidates are not produced yet.** Plan 04.
- **Nothing is cleaned yet.** The scanner produces candidates; validation and
  execution are plan 03. No test in this milestone moves, deletes or trashes
  anything outside a fixture it created.
- **No independent review took place.** Self-review of the full branch diff was
  performed; nobody else reviewed this work.
