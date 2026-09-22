# Changelog

Notable changes to MacDevClean. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[semantic versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

**Nothing has been released.** There is no tag, no signed build and no
published artifact. This section is the state of `develop`.

### Added

- Scanning for project artifacts with evidence — a parseable manifest in the
  same directory, and for `dist` also a `tsconfig.json` declaring it as output,
  Git ignoring it, and Git tracking nothing inside it.
- Global cache rules at exact home-relative locations for npm, yarn, pnpm, bun,
  pip, Cargo, Gradle, Homebrew, CocoaPods, pub, Xcode DerivedData and Archives,
  iOS DeviceSupport and CoreSimulator caches.
- Cleanup through `FileManager.trashItem` only, behind validated plan types
  whose initializers no other module can reach, with identity and existence
  rechecked immediately before every item.
- Docker integration over a verified local endpoint with allowlisted arguments
  and no shell, with irreversible operations confirmed separately.
- Large Files analysis inside folders the user explicitly chooses, always high
  risk and never preselected.
- Durable settings, project roots, exclusions and cleanup history in SwiftData.
  A corrupt store is never erased; cleanup is disabled instead and the
  interface says why.
- A native SwiftUI interface in English and Brazilian Portuguese, 240 catalog
  keys, with keyboard navigation and accessibility labels throughout.
- An unsigned universal local build, a drag-to-Applications disk image, and an
  artifact verifier that never accepts ad-hoc signing as a Developer ID
  signature.
- A signed, notarized release pipeline behind a protected GitHub environment,
  written and exercised against fake tools. It has never run against Apple.
- An original application icon.

### Fixed

Found when the owner ran the application for the first time, on 2026-09-21.
The six reports are in
[docs/superpowers/specs/2026-09-21-defect-report.md](docs/superpowers/specs/2026-09-21-defect-report.md).

- Counts reached the screen as raw `^[193 item](inflect: true)` markup. The
  catalog carried that annotation inside 13 values and declared no plural
  variations at all; four `Text` values were also built by concatenating
  strings, which selects the verbatim overload and skips the catalog entirely —
  one of them a whole sentence that stayed English in both languages. Counts
  are plural variations now, resolved in the locale the interface is showing.
- Large Files showed "not built yet" although plan 06 built the feature in
  full. Routing is data now, and a destination with no screen is not offered.
- The Caches toolbar could not fit the 1100 pt window minimum and pushed the
  whole screen past the window's height.
- "Start scan" was enabled where pressing it did nothing. It is disabled when
  it cannot act, says why, and offers what resolves it.
- Caches could not tell "nothing was found" from "the filters hide
  everything", and showed a blank area for both.
- Caches showed no sign that a scan was running.

### Known defects

- **The sidebar empties on some screens, leaving no way to navigate.** The
  column is not collapsed — it keeps its full width and draws no rows.
  Reproduced and narrowed by bisection; the cause is inside the detail screens'
  content and is not yet isolated. Reported for History and Exclusions as well,
  where the screens themselves are correct. Quitting and relaunching recovers,
  though AppKit persists the broken split-view geometry, so
  `defaults delete dev.macdevclean.app` may be needed. See
  [docs/verification/10-defects.md](docs/verification/10-defects.md).

### Deliberately not done

- No telemetry, no networking, no sandbox exception, no privileged helper, no
  background agent and no scheduled deletion.
- No "empty the Trash" command, and no permanent filesystem deletion.
- No claim that cleanup improves performance. Clearing a cache makes the next
  build slower.

### Not verified

- The 24 UI tests compile and have never run; the XCUITest gate is unavailable
  on the development machine. Measured on 2026-09-22, the blocker is narrower
  than previously recorded: launched normally, the application does expose its
  window to the accessibility interface, so whatever prevents XCUITest from
  seeing it is specific to the XCUITest launch.
- The Caches toolbar fix has not been seen on screen at the window minimum.
- Never launched on macOS 14, the declared minimum, and never run on Intel
  hardware.
- No signing, notarization, release, Homebrew tap or independent review.

Per-milestone evidence, with commands and exit statuses, is in
[docs/verification/](docs/verification/).
