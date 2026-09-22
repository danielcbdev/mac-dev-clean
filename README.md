# MacDevClean

A native macOS application that finds developer storage you can reclaim —
`node_modules`, build output, package caches, Xcode derived data, Docker
resources, large files in folders you choose — explains what each one costs you,
and moves filesystem items to the Trash.

[Português do Brasil](README.pt-BR.md)

> **Status: development complete, never published.** There is no release, no
> signed build, no Homebrew tap and no tag. Everything below that is measured
> says where it was measured; everything that has not been verified says so.

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
  background agent, no login item.** The app has no networking code of any kind.

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

## Installing

Build it yourself and open the unsigned artifact:
[docs/release/manual-install.md](docs/release/manual-install.md).

```bash
bash scripts/build-local.sh --version 1.0.0 --output dist/local
bash scripts/verify-artifact.sh --app dist/local/MacDevClean.app --mode unsigned
bash scripts/package-dmg.sh --app dist/local/MacDevClean.app \
    --output dist/MacDevClean-1.0.0-unsigned.dmg
```

| | Unsigned, today | Signed, not done |
|---|---|---|
| How you get it | Build it yourself | A published, notarized DMG |
| Gatekeeper | Refuses the first launch; Control-click → Open | Opens normally |
| Verified by | `verify-artifact.sh --mode unsigned` | `--mode signed`, which never accepts ad-hoc signing |
| Exists? | Yes | **No.** No certificate, no notarization, no release |

The signed pipeline is written and its failure modes are tested with fake
tools — no credentials means no signing, a failed signature or a rejected
notarization produces no artifact — but it **has never run against Apple**.
[docs/release/configuration.md](docs/release/configuration.md).

## Known limitations

- **The UI test suite has never run.** 21 tests compile; none is claimed to
  pass. No screenshots, no VoiceOver pass, no live performance measurement.
- **Never run on macOS 14, and never on Intel hardware.**
- **No signing, no notarization, no release, no Homebrew tap, no tag.**
- **No independent review.** Nobody else has reviewed this work.
- **Migration has never been exercised**, because there is only one schema
  version.
- **No licence has been chosen.** That is the owner's decision and was left
  open deliberately, so this repository ships no `LICENSE` file. Until one is
  chosen, default copyright applies and nobody else has permission to use,
  copy or redistribute it.

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
