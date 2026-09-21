# Progress

Single source of truth for resuming work. Update it at the end of every task.
Record only what actually happened: real commands, real exit status, real dates.

## Current state

- **Plan:** 08 quality (`docs/superpowers/plans/2026-09-21-08-quality.md`)
- **Branch:** feat/localization-accessibility
- **Last completed task:** 08 Task 2 — accessibility and window resilience
- **Next step:** 08 Task 3 — performance, privacy and regression gates
- **Latest partial evidence:** `MACDEVCLEAN_SKIP_UI_TESTS=1 bash
  scripts/verify.sh` exited 0 on 2026-09-21 after the localization and policy
  gates were added; UI tests remain not run, and the required 100,000-entry
  synthetic scan benchmark is still pending.
- **Blockers:** the XCUITest gate is unavailable on this machine. Ten UI tests
  are written and compile but cannot run: the app launches with no window
  visible to the accessibility interface. The committed plan 04 baseline fails
  identically, so this is environmental. See
  [docs/verification/05-interface.md](verification/05-interface.md).

## Repository baseline

The repository already existed on `main` with the planning bundle committed, so
it was preserved rather than reinitialized, as plan 01 Task 1 requires.

| Commit | Date | Subject |
|---|---|---|
| `8b3b588` | 2026-09-21 | initial commit (planning bundle) |
| `7ec895d` | 2026-09-21 | Update binary files (.DS_Store housekeeping) |
| `30e0ffe` | 2026-09-21 | docs: establish MacDevClean specification and engineering policy |

A remote named `origin` already existed when work started. Nothing has been
pushed. Publication requires separate authorization.

## Plan status

| Plan | Branch | Status |
|---|---|---|
| 01 foundation | feat/project-foundation | merged into develop |
| 02 scanning | feat/scanning-engine | merged into develop |
| 03 cleanup | feat/cleanup-safety | merged into develop |
| 04 Docker | feat/docker-integration | merged into develop |
| 05 interface | feat/app-shell | merged into develop |
| 06 large files | feat/large-files | merged into develop |
| 07 persistence | feat/history-and-exclusions | merged into develop |
| 08 quality | feat/localization-accessibility | in progress |
| 09 distribution | chore/release-pipeline | not started |

## Test evidence

Per-milestone evidence lives in `docs/verification/`. Each file records the
exact command, its exit status, the toolchain, the date and known omissions.

| Milestone | Evidence | Gate |
|---|---|---|
| 01 foundation | [01-foundation.md](verification/01-foundation.md) | `bash scripts/verify.sh` exit 0, 11 tests, 0 failures |
| 02 scanning | [02-scanning.md](verification/02-scanning.md) | `bash scripts/verify.sh` exit 0, 87 tests, 0 failures |
| 03 cleanup | [03-cleanup.md](verification/03-cleanup.md) | `bash scripts/verify.sh` exit 0, 126 tests, 0 failures |
| 04 Docker | [04-docker.md](verification/04-docker.md) | `bash scripts/verify.sh` exit 0, 202 tests, 0 failures |
| 05 interface | [05-interface.md](verification/05-interface.md) | 222 tests run, 0 failures; **10 UI tests NOT RUN** |
| 06 large files | [06-large-files.md](verification/06-large-files.md) | 242 tests run, 0 failures; **13 UI tests NOT RUN** |
| 07 persistence | [07-persistence.md](verification/07-persistence.md) | 271 tests run, 0 failures; **17 UI tests NOT RUN** |

## Known external blockers

- Remote CI has never been observed. `origin` exists but no push is authorized,
  so the GitHub Actions workflow is unverified against a real runner.
- The XCUITest gate is unavailable on this machine, so the interface has not
  been verified at runtime beyond its model tests.
- Signing, notarization and Homebrew publication need an Apple account,
  certificates, secrets and explicit authorization. None are configured.
