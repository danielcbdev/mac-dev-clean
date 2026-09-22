# Progress

Single source of truth for resuming work. Update it at the end of every task.
Record only what actually happened: real commands, real exit status, real dates.

## Current state

- **Plan:** redesign foundation
  (`docs/superpowers/plans/2026-09-22-00-redesign-foundation.md`)
- **Branch:** `feature/new-design` (the owner authorized reusing this branch
  directly, rather than cutting a new `feat/*` branch, for this plan)
- **Last completed task:** redesign-foundation Task 7 — all 6 tasks done,
  verification recorded
- **Next step:** per-screen redesign plans (Overview, Caches, History,
  Settings), each translating one or more of the spec's 13 screens
  (`docs/references/redesign/design-tokens.md`) into SwiftUI using the tokens
  this plan added
- **What this plan added:** `Theme` (22 color tokens, light/dark, from the
  approved Claude Design spec), `Typography` (5 type styles), a spacing/radius
  scale on `Layout`, `RiskBadge` restyled as a tinted pill, and
  `PrimaryButtonStyle`/`SecondaryButtonStyle`/`DestructiveButtonStyle`. Screen
  layouts (sidebar, cards, rings, tables) are not yet redesigned — this plan
  was foundation-only.
- **A locale bug found and fixed along the way:** the new `RiskBadgeTests`
  exposed that `RiskBadge.title` used `String(localized:)`, which resolves
  the process's preferred localization rather than an explicit locale — the
  same bug `LocalizedFormatters.text(_:locale:)` was already written to work
  around elsewhere in this codebase. `RiskBadge.title` now routes through it.
- **Latest evidence:** `MACDEVCLEAN_SKIP_UI_TESTS=1 bash scripts/verify.sh`
  exited 0 on 2026-09-22, Xcode 27.0 (Build 27A266a), Swift 6.4. Swift package
  tests: 21 cases, 0 failures. App unit tests: 83 cases, 0 failures (16 of
  them new: `ColorSupportTests`, `ThemeColorTests`, `TypographyTests`,
  `LayoutScaleTests`, `RiskBadgeTests`, `ButtonStyleTests`). UI tests: not
  run (same known blocker as milestone 10, below). Release build (unsigned):
  succeeded. Lint: no findings.
- **Two corrections to documents this repository held (from plan 10, still
  true):** plan 10 states that Brazilian Portuguese puts zero in CLDR's
  `other` category — it puts it in `one` — and the defect report's proposed
  cause for D3 was wrong, because the sidebar column is never collapsed, only
  empty.
- **Blockers:** the XCUITest gate is still unavailable, measured as specific
  to the XCUITest launch rather than to the application. **No CI run has ever
  happened**: the GitHub Actions API reports zero workflows and zero runs.
  Publication, signing and the tag remain unauthorized and undone.

## Repository baseline

The repository already existed on `main` with the planning bundle committed, so
it was preserved rather than reinitialized, as plan 01 Task 1 requires.

| Commit | Date | Subject |
|---|---|---|
| `8b3b588` | 2026-09-21 | initial commit (planning bundle) |
| `7ec895d` | 2026-09-21 | Update binary files (.DS_Store housekeeping) |
| `30e0ffe` | 2026-09-21 | docs: establish MacDevClean specification and engineering policy |

A remote named `origin` already existed when work started —
`git@github.com:danielcbdev/mac-dev-clean.git`, public, default branch `main`.

**Pushed on 2026-09-22, with the owner's explicit authorization in session.**
Branches only; `git ls-remote --tags origin` is empty and `v1.0.0` does not
exist.

| Remote branch | Commit |
|---|---|
| `main` | `30e0ffe` — fast-forward from `7ec895d` |
| `develop` | `29e667e` |
| `release/1.0.0` | `29e667e` |

Publishing a release, signing and tagging still require separate
authorization and are not done.

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
| 08 quality | feat/localization-accessibility | merged into develop |
| 09 distribution | chore/release-pipeline | merged into develop |
| 10 defect remediation | fix/interface-defects | merged into develop — all six defects fixed |
| redesign foundation | feature/new-design | in progress — design tokens landed, screens not yet redesigned |

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
| 08 quality | [08-quality.md](verification/08-quality.md) | `bash scripts/verify.sh` exit 0, 278 tests run, 0 failures; **21 UI tests NOT RUN** |
| 09 distribution | [09-distribution.md](verification/09-distribution.md) | `bash scripts/verify.sh` exit 0, 278 tests run, 0 failures, 66 contract assertions; **21 UI tests NOT RUN** |
| 10 defects | [10-defects.md](verification/10-defects.md) | `bash scripts/verify.sh` exit 0, 295 tests run, 0 failures; **24 UI tests NOT RUN**; all six defects fixed and confirmed on screen |

## Known external blockers

Each of these needs something this machine or this session does not have. None
is a defect in the code, and none is recorded as done.

| Blocker | What it needs |
|---|---|
| The XCUITest gate | A logged-in macOS session where an app launched by XCUITest exposes its window to the accessibility interface. Narrowed on 2026-09-22: launched with `open`, the app *is* exposed and inspectable, so the blocker is in the XCUITest launch |
| Screenshots, VoiceOver, appearance checks | The same, plus screen-recording permission |
| Live performance measurement | The same |
| Remote CI | Branches are pushed. The Actions API reports zero workflows and zero runs for the repository; `main`, the default branch, carries no `workflows/` directory. The UI suite has never run on any runner |
| Signing and notarization | An Apple Developer membership, a Developer ID certificate and an App Store Connect key. None is configured |
| Homebrew tap | A published release URL and checksum, and authorization to create the tap repository |
| macOS 14 support | A macOS 14 machine. Only macOS 27.0 was available |
| Intel support | An Intel Mac. Only Apple Silicon was available |
| A licence | The owner's decision. Deliberately not made on their behalf |
| `v1.0.0` | Every gate in [docs/release/checklist.md](release/checklist.md). Most are unchecked, so the tag was not created |
