# Plan 08 quality verification

**Date:** 2026-09-21
**Branch:** `feat/localization-accessibility`
**Toolchain:** Xcode 27.0 (27A266a), macOS 27.0 (26A428), Apple M4, 24 GiB RAM

## Gate result

```text
$ MACDEVCLEAN_SKIP_UI_TESTS=1 bash scripts/verify.sh
exit status: 0
==> verify.sh: all checks that ran passed — UI tests NOT RUN
```

| Check | Result |
|---|---|
| `swift test --package-path Packages/MacDevCleanCore` | **Pass** — 232 tests, 0 failures |
| App unit tests, Debug | **Pass** — 46 tests, 0 failures |
| **UI tests** | **NOT RUN** — 21 written, the XCUITest gate is unavailable on this machine |
| Release build, unsigned | **Pass** |
| `bash scripts/check-token-access.sh` | **Pass** |
| `bash scripts/tests/check-localization-tests.sh` + `swift scripts/check-localization.swift` | **Pass** — 232 catalog keys, both languages |
| `bash scripts/tests/check-policy-tests.sh` + `bash scripts/check-policy.sh` | **Pass** — after the fix below |
| `bash scripts/lint.sh` | **Pass** |
| `git diff --check` | **Pass** |
| Remote CI | **Not run** — no push authorized |

| Suite | Tests | Failures |
|---|---:|---:|
| `DomainTests` | 1 | 0 |
| `TestSupportTests` | 6 | 0 |
| `CleanupRulesTests` | 21 | 0 |
| `CleanupTests` | 39 | 0 |
| `ScanningTests` | 70 | 0 |
| `DockerIntegrationTests` | 76 | 0 |
| `PersistenceTests` | 19 | 0 |
| `MacDevCleanAppTests` | 46 | 0 |
| **Total run** | **278** | **0** |
| `MacDevCleanUITests` | 21 | **not run** |

## The static policy check was not checking anything

The first gate run of this session **failed**, at
`scripts/tests/check-policy-tests.sh`:

```text
Policy check passed
Expected FileManager.removeItem fixture to fail policy validation
```

`scripts/check-policy.sh` searched with ripgrep. **ripgrep is not installed on
this machine**: `rg` exists only as a shell function in the interactive zsh
session, which a `bash` script never sees. Every rule ran `rg … || true`, so a
missing binary produced no output, which read as no matches, which printed
"Policy check passed". All five rules were passing vacuously.

The negative fixture is the only reason this was caught, which is exactly what
it is for. Two changes:

- The checker now uses POSIX `grep -R -E`, which ships with macOS, so the check
  cannot be skipped by a missing tool. The patterns are POSIX extended regular
  expressions, which ripgrep would also accept. A tooling dependency that is not
  installed is worse than no dependency.
- Every rule now has a fixture that must be rejected —
  `policy-remove-item`, `policy-unlink`, `policy-shell-exec`,
  `policy-private-path`, `policy-telemetry` — plus a tree with no production
  sources, which must fail rather than pass vacuously. `policy-valid` gained
  deliberate near misses (`FileManager.default.trashItem`, `confirm(`) so the
  rules cannot be tightened into over-matching.

After the fix the whole gate exits 0 with the numbers in the table above.

**The exit-0 run recorded in this file's previous revision covered a policy
check in that broken state.** Its package, app, build, localization and lint
results stand; its policy line did not verify anything. This run replaces it.

## An unknown size stopped announcing what it was

Reviewing the branch diff before the merge found a second defect. Task 1 routed
`ByteLabel`'s accessibility label through the new byte formatter, so a size that
could not be measured announced itself as "Unavailable". Beside a visible row
label that reads acceptably; VoiceOver reads the label on its own, where it says
nothing about *what* is unavailable, and
[docs/design/layout.md](../design/layout.md) states these are announced as
"Size could not be measured".

`LocalizedFormatters.accessibleBytes(_:locale:)` restores the full sentence in
both languages, and `testAnUnknownSizeIsAnnouncedAsUnmeasuredRatherThanAsUnavailable`
pins it. The visible text is unchanged: still "Unavailable" / "Indisponível",
never "0 bytes".

The date formatter also took an explicit time zone. Its test asserted a
calendar day rendered in the host's zone, which is the same instant on two
different dates either side of midnight — the assertion would have passed or
failed depending on where it ran. It is now pinned to UTC, with an Auckland
case as the control.

## Scan performance

```bash
swift test --package-path Packages/MacDevCleanCore --filter ScanPerformanceTests
```

Two tests, passing, inside the 70 `ScanningTests`:

- deterministic cancellation after the first 256-entry batch of a lazily
  represented 100,000-entry Node tree, with no more than two batches read;
- an owned real-file fixture of 5,000 one-byte files, created, scanned and
  removed in 1.079 seconds.

That duration includes fixture setup and teardown, so it is regression
coverage, not a throughput figure. See
[docs/testing/performance.md](../testing/performance.md).

## Known omissions

- **UI tests have not run.** A direct attempt on 2026-09-21 built and launched,
  then failed waiting for `scan.start` in five successive tests and was
  interrupted after 104 seconds, exiting 75 with `** TEST INTERRUPTED **`. Not
  a pass.

  ```bash
  xcodebuild -workspace MacDevClean.xcworkspace -scheme MacDevClean \
    -destination 'platform=macOS' -derivedDataPath .build/xcode \
    -only-testing:MacDevCleanUITests test
  ```

- **No live performance measurement.** No p50/p95 navigation response, Cancel
  latency, peak memory, or full 100,000-entry throughput was measured, because
  all of them require the application to be driveable under XCUITest.
- **No screenshots, no VoiceOver pass, no appearance inspection.** The normal
  Debug app did expose its accessibility tree in a limited manual inspection,
  which is not the XCUITest launch context and is not a substitute for the
  pending checks.
- The checks that need a person, real hardware or credentials are listed in
  [docs/testing/manual-release-checks.md](../testing/manual-release-checks.md).
  None of them has been performed.
- **No independent review took place.**
