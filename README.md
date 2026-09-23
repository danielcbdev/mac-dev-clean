# MacDevClean

A native macOS application that finds developer storage you can reclaim —
`node_modules`, build output, package caches, Xcode derived data, Docker
resources, large files in folders you choose — explains what each one costs you,
and moves filesystem items to the Trash.

[Português do Brasil](README.pt-BR.md)

> **Status: unsigned development build published, signed release not done.**
> [`v1.0.0-unsigned`](https://github.com/danielcbdev/mac-dev-clean/releases/tag/v1.0.0-unsigned)
> is a real, downloadable GitHub pre-release. There is no signed build, no
> notarization and no Homebrew tap yet. Everything below that is measured says
> where it was measured; everything that has not been verified says so.

## Installing

Download the disk image from the [latest release](https://github.com/danielcbdev/mac-dev-clean/releases/tag/v1.0.0-unsigned)
and run:

```bash
curl -L -o MacDevClean.dmg \
  https://github.com/danielcbdev/mac-dev-clean/releases/download/v1.0.0-unsigned/MacDevClean-1.0.0-unsigned.dmg
curl -L -o MacDevClean.dmg.sha256 \
  https://github.com/danielcbdev/mac-dev-clean/releases/download/v1.0.0-unsigned/MacDevClean-1.0.0-unsigned.dmg.sha256
shasum -a 256 -c MacDevClean.dmg.sha256   # optional, confirms the download
open MacDevClean.dmg
```

Drag `MacDevClean.app` into `/Applications`. This build is **unsigned and not
notarized**, so the first launch is refused — **Control-click the app → Open**,
then confirm. That approves this one application; do not disable Gatekeeper.
Full detail, including what the app writes to disk and how to remove it:
[docs/release/manual-install.md](docs/release/manual-install.md).

### Building it yourself

Same unsigned artifact, built from source instead of downloaded:

```bash
bash scripts/build-local.sh --version 1.0.0 --output dist/local
bash scripts/verify-artifact.sh --app dist/local/MacDevClean.app --mode unsigned
bash scripts/package-dmg.sh --app dist/local/MacDevClean.app \
    --output dist/MacDevClean-1.0.0-unsigned.dmg
```

| | Unsigned, today | Signed, not done |
|---|---|---|
| How you get it | Download the release, or build it yourself | A published, notarized DMG |
| Gatekeeper | Refuses the first launch; Control-click → Open | Opens normally |
| Verified by | `verify-artifact.sh --mode unsigned` | `--mode signed`, which never accepts ad-hoc signing |
| Exists? | Yes — the pre-release above | **No.** No certificate, no notarization |

The signed pipeline is written and its failure modes are tested with fake
tools — no credentials means no signing, a failed signature or a rejected
notarization produces no artifact — but it **has never run against Apple**.
[docs/release/configuration.md](docs/release/configuration.md).

## What it will not do

This matters more than the feature list.

- **Moving to the Trash does not free space.** Space comes back when you empty
  the Trash in Finder, which this app never does for you. The interface says
  "Potential cleanup", never "reclaimable", and reports bytes moved to the
  Trash, Docker's reported reclaim, and the observed free-space change as three
  separate numbers — never as one total.
- **It will not make your machine faster.** A cache that is cleared gets
  rebuilt. The next build is slower, not faster. Nothing here claims otherwise.
- **It never empties the Trash, and never calls `rm`, `rmdir` or
  `removeItem`.** Filesystem cleanup is `FileManager.trashItem` and nothing
  else — a static check and a behavioural suite both enforce it.
- **Nothing is selected by a scan.** You select. High-risk items cannot be
  selected from the list at all; they sit behind a disclosure you open
  deliberately, and "select all low and medium risk" never reaches them.
- **Docker operations are not recoverable.** They are labelled as such, confirmed
  separately, and restricted to resources reviewed by identifier.
- **No telemetry, no network, no sandbox exception, no privileged helper, no
  background agent, no login item.** No production source uses a networking
  API, the gate fails if one appears, and `otool -L` on the built binary lists
  no networking library.

## What it detects

Detection needs evidence, never a directory name.

| Kind | Examples | Evidence required |
|---|---|---|
| Project artifacts | `node_modules`, `.turbo`, `dist`, Flutter `build`, `.dart_tool` | A parseable manifest in the same directory; `dist` additionally needs a `tsconfig.json` declaring it as output, Git ignoring it, and Git tracking nothing inside it |
| Global caches | npm, yarn, pnpm, bun, pip, Cargo, Gradle, Homebrew, CocoaPods, pub, Xcode DerivedData and Archives, iOS DeviceSupport, CoreSimulator caches | An exact home-relative location declared by the rule. No pattern matching, and no tool is run to ask where its cache lives |
| Large files | Files above a threshold | Only inside folders you explicitly chose for this feature. Always high risk, never preselected |
| Docker | Images, containers, volumes, build cache | A verified local endpoint, allowlisted arguments, never a shell |

`~/.gradle` as a whole, `~/.cargo/bin`, Homebrew's Cellar, `CoreSimulator/Devices`
and SDKs are **deliberately excluded**. The reasoning for every rule, and for
every exclusion, is in [docs/cleanup-rules.md](docs/cleanup-rules.md).

## Screenshots

**There are none, and none are invented.** The screenshots belong with the UI
test suite, which compiles but has never run on this machine — the application
launches under XCUITest without exposing a window to the accessibility
interface. See [docs/verification/05-interface.md](docs/verification/05-interface.md)
for the investigation and [docs/demo/README.md](docs/demo/README.md) for exactly
how to produce them from fixture data.

The application icon, drawn by `scripts/make-appicon.swift`, is at
[MacDevCleanApp/Resources/Assets.xcassets/AppIcon.appiconset](MacDevCleanApp/Resources/Assets.xcassets/AppIcon.appiconset).

## Architecture

Dependencies point inward. `Domain` imports nothing but Foundation.

```text
             ┌──────────────────────────────────────────┐
             │              MacDevCleanApp              │
             │  SwiftUI · Observation · AppKit · OSLog  │
             └────────────────────┬─────────────────────┘
                                  │
   ┌───────────┬─────────────┬────┴────────┬──────────────┬─────────────┐
   │ Scanning  │   Cleanup   │ CleanupRules│DockerIntegra.│ Persistence │
   │           │             │             │              │  SwiftData  │
   └─────┬─────┴──────┬──────┴──────┬──────┴───────┬──────┴──────┬──────┘
         │            │             │              │             │
         └────────────┴─────────────┴──────┬───────┴─────────────┘
                                           │
                                    ┌──────┴──────┐
                                    │   Domain    │
                                    │ Foundation  │
                                    └─────────────┘
```

Cleanup authority lives in `Cleanup` and nowhere else. The executor accepts only
`ValidatedCleanupItem` values, whose initializers are internal to that module,
so no other target — including the interface — can construct one. A script
type-checks a deliberate forgery attempt and **fails if it compiles**:

```bash
bash scripts/check-token-access.sh
```

Decisions, with their rejected alternatives and consequences, are in
[docs/adr/](docs/adr/).

## Tech stack and engineering practices

**Language and concurrency.** Swift 6 in strict language mode
(`.swiftLanguageMode(.v6)` on every target). Core targets are
`nonisolated` by default — Swift 6's own default, kept explicit rather than
inherited — and only the app layer opts into `@MainActor`, written out rather
than assumed.

**Frameworks — zero third-party dependencies.** `Package.resolved` has no
entries. Everything is Apple-native: SwiftUI + `Observation` for the
interface (no Combine, no legacy `ObservableObject`), AppKit only where
SwiftUI has no equivalent, `SwiftData` for local persistence,
`CryptoKit` for content hashing, `OSLog` for logging.

**Modular architecture.** A local Swift package (`Packages/MacDevCleanCore`)
split into six targets — `Domain`, `CleanupRules`, `Scanning`, `Cleanup`,
`DockerIntegration`, `Persistence` — with dependencies pointing inward only;
`Domain` imports nothing but Foundation. This isn't just documented: cleanup
authority is a type-level boundary (`ValidatedCleanupItem` has an internal
initializer, so only `Cleanup` can construct one), and
`scripts/check-token-access.sh` type-checks a deliberate forgery attempt and
fails the build if it *compiles*.

**Testing.** Dual frameworks by design — XCTest for app-hosted and UI tests,
Swift's newer `Testing` framework (`@Test`) for package-level suites — written
test-first, red before green, one behavioural case at a time. Every
destructive path (Trash, Docker) is exercised against fixtures the test
itself creates, a fake Trash and a fake Docker client, so the suite never
touches a real machine.

**Static analysis, hand-built.** `scripts/check-policy.sh` proves production
Swift never calls `rm`, `rmdir`, `removeItem` or a networking API — plain
POSIX `grep`, deliberately not `ripgrep`, because a missing optional tool that
silently no-ops a gate is worse than no gate. `scripts/check-localization.swift`
is a standalone Swift script (no package, no target) that verifies every
string key exists in both locales with matching plural placeholders and no
stale entries. `.swift-format` (100-column, one blank line max) runs from the
pinned Xcode toolchain itself — nothing downloaded, nothing floating.

**CI/CD — 3 GitHub Actions workflows, all pinned, all least-privilege.**
- `CI` — full gate on every PR and push to `main`/`develop`, `permissions:
  contents: read`, no secrets in reach.
- `Performance` — manual only (`workflow_dispatch`); measures scan
  performance without asserting a wall-clock threshold, because a number from
  a shared runner isn't comparable to one from a laptop and an
  unreproducible threshold just becomes a flaky test.
- `Release` — three stages (test → sign & notarize → publish); the signing
  stage runs only inside a protected `release` environment with a required
  reviewer, and the publish stage is the only job in the whole pipeline
  allowed to write. Every third-party Action is pinned to an immutable commit
  SHA, never a floating tag.

**Release engineering.** `scripts/release-preflight.sh` refuses a signed
release by naming exactly which secrets are missing — never a value, a
length or a prefix. `scripts/sign-notarize.sh` builds a throwaway keychain per
run and guarantees its teardown on any exit path, including failure.
`scripts/render-cask.rb` generates the Homebrew Cask from five validated
arguments — never string interpolation into Ruby source — and its own
contract-test suite asserts a Cask is never produced for an artifact that
isn't actually published.

**Documentation as engineering, not an afterthought.** 6 ADRs record
*rejected* alternatives and their consequences, not just the decision taken.
Verification docs under `docs/verification/` record the actual command, exit
status and toolchain used — a check that didn't run is written down as not
run, never quietly counted as a pass.

**Git workflow.** Conventional Commits throughout (80 commits, `feat:`,
`fix:`, `merge:`, `chore:`, `docs:`). Branch lifecycle is
`main → develop → feat/*`, merged back with `--no-ff` so feature history stays
intact instead of being squashed away.

## Requirements

| | |
|---|---|
| Runs on | macOS 14 or later — **a deployment target, not an observation**; only macOS 27.0 was available |
| Built with | Xcode 27.0 (27A266a), Swift 6.4 |
| Architectures | `arm64` and `x86_64` — the Intel slice **has never been run on Intel hardware** |
| Dependencies | None. Apple frameworks only |

## Building and testing

```bash
git clone <this repository>
cd mac-dev-clean
bash scripts/verify.sh
```

The gate runs the package tests, the app unit tests, the UI tests, an unsigned
Release build, the cleanup-authority check, the localization checker and its
fixtures, the release script contracts, the static policy check and its
fixtures, the linter, and a whitespace check. It exits 0 only if everything that
ran passed.

Where the UI suite cannot run, set `MACDEVCLEAN_SKIP_UI_TESTS=1`. The gate then
prints **MISSING GATE**, changes its final line, and is not a pass:

```bash
MACDEVCLEAN_SKIP_UI_TESTS=1 bash scripts/verify.sh
```

Individual suites:

```bash
swift test --package-path Packages/MacDevCleanCore
swift test --package-path Packages/MacDevCleanCore --filter ScanPerformanceTests
bash scripts/tests/release-contract-tests.sh
```

Every destructive test runs against fixtures it created, with a fake Trash and a
fake Docker. No test touches your caches, your Trash or your Docker resources.

## Known limitations

- **The UI test suite has never run.** 21 tests compile; none is claimed to
  pass. No screenshots, no VoiceOver pass, no live performance measurement.
- **Never run on macOS 14, and never on Intel hardware.**
- **No signing, no notarization, no Homebrew tap.** An unsigned development
  build is published as a GitHub pre-release,
  [`v1.0.0-unsigned`](https://github.com/danielcbdev/mac-dev-clean/releases/tag/v1.0.0-unsigned).
- **No independent review.** Nobody else has reviewed this work.
- **Migration has never been exercised**, because there is only one schema
  version.
- **Licensed under MIT.** See `LICENSE`.

Full evidence, per milestone, with commands and exit statuses:
[docs/verification/](docs/verification/). What still needs a person, real
hardware or credentials:
[docs/testing/manual-release-checks.md](docs/testing/manual-release-checks.md).

## Documentation

| | |
|---|---|
| Engineering contract | [AGENTS.md](AGENTS.md) |
| Cleanup rules | [docs/cleanup-rules.md](docs/cleanup-rules.md) |
| Decisions | [docs/adr/](docs/adr/) |
| Security | [docs/security/](docs/security/) |
| Interface layout | [docs/design/layout.md](docs/design/layout.md) |
| Testing evidence | [docs/testing/](docs/testing/), [docs/verification/](docs/verification/) |
| Release | [docs/release/](docs/release/) |
| Changes | [CHANGELOG.md](CHANGELOG.md) |

Copyright © 2026 Daniel Carvalho. The icon and all source in this repository are
original work.
