# Verification — plan 04, Docker integration

- **Date:** 2026-09-21
- **Branch:** `feat/docker-integration`
- **Toolchain:** Xcode 27.0 (27A266a); Apple Swift 6.4; macOS 27.0 (26A428); arm64

## Gate result

```text
$ bash scripts/verify.sh
exit status: 0
```

| Check | Result |
|---|---|
| `swift test --package-path Packages/MacDevCleanCore` | **Pass** — 198 tests, 0 failures |
| App tests, Debug | **Pass** — `** TEST SUCCEEDED **` |
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
| `MacDevCleanAppTests` | 3 | 0 |
| `MacDevCleanUITests` | 1 | 0 |
| **Total** | **202** | **0** |

## Exit-gate checks

**All Docker tests pass with no real daemon.** Every one of the 76
`DockerIntegrationTests` answers from `RecordingProcessRunner`, which launches
nothing. The only tests that start a real process are the eleven
`ProcessRunnerTests`, and they use `/usr/bin/printf`, `/bin/ls`, `/bin/sleep`,
`/usr/bin/yes` and `/usr/bin/printenv`. **No test has contacted a Docker
daemon.**

**A remote context is never cleaned.**
`testARemoteContextIsRejectedBeforeAnyDaemonCall` asserts both the refusal *and*
that exactly one command — the context inspection — was issued, so a remote
daemon is never even spoken to. `testEveryNonLocalEndpointSchemeIsRejected`
covers `ssh://`, `tcp://` including `tcp://127.0.0.1`, `https://`, `http://`,
`npipe://`, `fd://`, empty and whitespace.

**A context repointed at another daemon is caught.**
`testTheFingerprintBindsEndpointAndDaemonRatherThanTheContextName` keeps the
name identical and changes the daemon `ID`, and asserts the fingerprints differ.
`testADaemonThatChangedBehindTheContextNameIsRejected` asserts revalidation
refuses in that case.

**Missing or changed JSON fails closed.** `ParserTests` covers a missing
identifier, malformed JSON, unknown fields, a missing size, a negative size, an
oversized value, a human-readable size, a missing `Reclaimable`, a missing
`Mutable`, a string where a boolean belongs, a missing container `State` and a
missing `Running` flag. In every case the outcome is refusal or explicit unknown
— never eligibility.

**A volume referenced by a stopped container is still in use.**
`testAVolumeHeldByAStoppedContainerIsNotOffered` and
`testAnImageHeldByAStoppedContainerIsNotOffered` both use a container in state
`exited`. `testAVolumeAttachedSinceTheReviewIsRejected` asserts the same at
revalidation time.

**Stopped containers are high risk.**
`testOnlyStoppedContainersAreOfferedAndTheyAreHighRisk` asserts `.high`,
tightening the approved table as the implementation clarifications require.

**A resource that changed after review cannot be removed.**
`testAContainerThatStartedAgainIsRejected`,
`testAVolumeAttachedSinceTheReviewIsRejected`,
`testAnImageAnsweringToSeveralNamesIsRefused` and
`testAResourceInUseAtWriteTimeIsReportedAsChanged`.

**A timed-out write is never retried blindly.** Three tests cover the three
answers: `testATimeoutThatTurnsOutToHaveSucceededIsNotRetried` asserts exactly
one write was issued; `testATimeoutWhereTheResourceSurvivedIsAFailure`;
`testATimeoutNobodyCanSettleIsReportedAsIndeterminate`.

**Every irreversible action is exact-target and allowlisted.** `CommandTests`
pins the exact argument array for all four operations and asserts the absence of
`--all`, `--volumes`, `system`, broad `prune` and any `--force` outside the one
pinned `buildx prune`. Hostile identifiers — option-like, punctuated, containing
newlines or NUL — are refused before they can become an argument.

**Missing or remote Docker does not disrupt filesystem features.** Docker is a
separate target with its own client; nothing in `Scanning` or `Cleanup` imports
it. `testAnOfflineDaemonIsUnavailable` returns `.unavailable` rather than
throwing something the app cannot present, and the 55 `ScanningTests` and 39
`CleanupTests` all pass with no Docker present at all.

**A builder that is not usable disables only its own feature.**
`testABuilderOnARemoteNodeDisablesOnlyBuildCacheCleanup` and
`testAnUnknownBuildxCapabilityDisablesOnlyBuildCacheCleanup` both assert the
daemon identity is still discovered and the rest of the integration still works.

## A defect these tests caught

`settleAfterTimeout` originally reused the inventory's container-inspection
helper, which swallows read errors so that one unreadable container cannot spoil
a whole scan. In the post-timeout path that behaviour was actively dangerous: an
inspection that *could not run* returned an empty list, which read as "the
resource is gone", which read as "the write succeeded".

`testATimeoutNobodyCanSettleIsReportedAsIndeterminate` failed on exactly that.
The path now uses a dedicated three-state probe — present, absent, unknown —
where only an explicit "no such" from the daemon counts as absence.

## Known omissions and limitations

- **No live Docker testing has been performed.** It requires the owner's
  explicit authorisation and disposable resources. Nothing in the automated
  suite can do it, and no claim about a real daemon is made anywhere in this
  repository.
- **Fixtures are synthetic**, written from the documented schemas. Sanitized
  captured output can replace them without changing a test, since the parsers
  are what the tests exercise.
- **Buildx text parsing.** Builder locality is determined by reading the
  `Endpoint:` lines of `buildx inspect`, because a stable JSON form of that
  command cannot be relied on across versions. An unparseable response disables
  build-cache cleanup rather than guessing.
- **Docker inventory is not yet merged with filesystem scan results.** That
  composition happens in the application, in plan 05.
- **No independent review took place.** Self-review of the full branch diff was
  performed; nobody else reviewed this work.
