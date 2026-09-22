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
- A native SwiftUI interface in English and Brazilian Portuguese, 232 catalog
  keys, with keyboard navigation and accessibility labels throughout.
- An unsigned universal local build, a drag-to-Applications disk image, and an
  artifact verifier that never accepts ad-hoc signing as a Developer ID
  signature.
- A signed, notarized release pipeline behind a protected GitHub environment,
  written and exercised against fake tools. It has never run against Apple.
- An original application icon.

### Deliberately not done

- No telemetry, no networking, no sandbox exception, no privileged helper, no
  background agent and no scheduled deletion.
- No "empty the Trash" command, and no permanent filesystem deletion.
- No claim that cleanup improves performance. Clearing a cache makes the next
  build slower.

### Not verified

- The 21 UI tests compile and have never run; the XCUITest gate is unavailable
  on the development machine.
- Never launched on macOS 14, the declared minimum, and never run on Intel
  hardware.
- No signing, notarization, release, Homebrew tap or independent review.

Per-milestone evidence, with commands and exit statuses, is in
[docs/verification/](docs/verification/).
