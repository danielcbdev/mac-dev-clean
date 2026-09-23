# Progress

Single source of truth for resuming work. Update it at the end of every task.
Record only what actually happened: real commands, real exit status, real dates.

## Current state

- **Plan:** cleanup progress and scan reset (owner request on 2026-09-23;
  there is no numbered plan file). The redesign notes below are prior work.
- **Branch:** `feat/cleanup-progress-and-scan-reset`, cut from `develop`.
  Merged into `develop` (`eb6903c`) and from there into `main` (`c99e066`)
  on 2026-09-23, with the owner's explicit authorization in session. Both
  branches pushed to `origin`.
- **Last completed task:** show cleanup progress while items move to the
  Trash, and invalidate the scan after a cleanup that moved or removed
  anything. Evidence:
  [cleanup-progress-and-scan-reset.md](verification/cleanup-progress-and-scan-reset.md).
  Published as the `v1.0.1-unsigned` GitHub pre-release (see below).
- **Next step:** the redesign track's next screen is still Caches (spec
  screens `1c`, `1d`, `1k`, `1l`).
- **What the Overview plan added:** restyled sidebar chrome (background,
  wordmark, footer, selected/unselected item highlight), the Overview header,
  the potential-cleanup ring and its primary button, the categories card and
  row, the Docker card, the three info cards, and two new full-screen states
  (`NeverScannedView`, `ScanningStateView`) — all using the foundation plan's
  `Theme`/`Typography`/`Layout`/button-style tokens.
- **Two defects the owner found on manual review, both fixed:** (1)
  `NeverScannedView`/`ScanningStateView` introduced English copy with no
  `Localizable.xcstrings` entry, so it showed in English regardless of the
  selected language — fixed by adding the 4 genuinely new catalog entries
  (en + pt-BR) and reusing existing keys elsewhere rather than duplicating
  them. (2) the "with results" layout didn't match the spec — the sidebar's
  selected-item highlight was never implemented (only container chrome was),
  and the results grid was an equal 50/50 split instead of the spec's
  `minmax(0,1fr) 520px` (ring flexible, categories fixed at 520pt). Both
  fixed and re-verified.
- **A locale bug found and fixed in the foundation plan:** the new
  `RiskBadgeTests` exposed that `RiskBadge.title` used `String(localized:)`,
  which resolves the process's preferred localization rather than an
  explicit locale — the same bug `LocalizedFormatters.text(_:locale:)` was
  already written to work around elsewhere in this codebase. `RiskBadge.title`
  now routes through it.
- **Latest evidence:** on 2026-09-23, `bash scripts/verify.sh` exited 65
  (package tests 232, 0 failures; app unit tests 89, 0 failures; UI tests
  24 run, 24 failed; later checks not run). The same day
  `MACDEVCLEAN_SKIP_UI_TESTS=1 bash scripts/verify.sh` exited 0. UI tests
  in that second command were not run. Details in
  [cleanup-progress-and-scan-reset.md](verification/cleanup-progress-and-scan-reset.md).
- **Two corrections to documents this repository held (from plan 10, still
  true):** plan 10 states that Brazilian Portuguese puts zero in CLDR's
  `other` category — it puts it in `one` — and the defect report's proposed
  cause for D3 was wrong, because the sidebar column is never collapsed, only
  empty.
- **Blockers:** the XCUITest gate is still unavailable, measured as specific
  to the XCUITest launch rather than to the application. **No CI run has ever
  happened**: the GitHub Actions API reports zero workflows and zero runs.
  Signing remains unauthorized and undone. Unsigned publication is now done
  twice (`v1.0.0-unsigned`, `v1.0.1-unsigned`), each with the owner's explicit
  authorization in session.
- **v1.0.1-unsigned release, 2026-09-23:** `feat/cleanup-progress-and-scan-reset`
  merged into `develop` (`eb6903c`), README version references bumped
  (`3cf5a7c`), `develop` merged into `main` (`c99e066`); both branches pushed
  to `origin`. Tag `v1.0.1-unsigned` created on `main` and pushed. Artifact
  built with `bash scripts/build-local.sh --version 1.0.1 --output dist/local`,
  passed `scripts/verify-artifact.sh --mode unsigned`, packaged with
  `scripts/package-dmg.sh`. SHA-256:
  `4152d7d77604e8aec1946e01175d823957794a875064893de95a8e251c581fd8`.
  Published as a GitHub pre-release:
  https://github.com/danielcbdev/mac-dev-clean/releases/tag/v1.0.1-unsigned.
  Still unsigned, still not notarized — the checklist gates in
  [docs/release/checklist.md](release/checklist.md) beyond "unsigned pre-release
  authorized" remain unmet.

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
| redesign foundation | feature/new-design | complete (commits landed directly on this branch) — design tokens |
| redesign overview screen | feature/new-design | complete (commits landed directly on this branch) — sidebar and Overview's 4 states |

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
| cleanup progress | [cleanup-progress-and-scan-reset.md](verification/cleanup-progress-and-scan-reset.md) | `bash scripts/verify.sh` exit 65 (24 UI tests failed); skip-UI rerun exit 0, 232 package + 89 app unit tests, 0 failures; **UI tests NOT RUN** on the rerun. Rerun again immediately before merging, same result, exit 0 |

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
| A **signed** `v1.0.1` (or any signed tag) | Every remaining gate in [docs/release/checklist.md](release/checklist.md) — signing/notarization credentials, a second machine for the download-as-a-stranger check, macOS 14 and Intel hardware. `v1.0.0-unsigned` and `v1.0.1-unsigned` are both real, published, unsigned pre-releases; a signed release has never been built |
