# MacDevClean Product and Architecture Specification

**Status:** Approved by the user for implementation planning  
**Product:** MacDevClean  
**Initial release:** 1.0.0  
**Minimum platform:** macOS 14 Sonoma  
**Primary language:** English  
**Supported localization:** Portuguese (Brazil)  

Companion: [implementation clarifications](2026-09-21-implementation-clarifications.md) records technical corrections made during planning; read both documents before execution.

## 1. Product intent

MacDevClean is a native macOS desktop application that helps developers understand and safely reclaim disk space consumed by dependency directories, build artifacts, tool caches, Xcode data, Docker resources, and explicitly selected large files.

The application is both a useful personal tool and a production-quality portfolio project. Its implementation must demonstrate sound macOS engineering, explicit safety boundaries, testable architecture, accessibility, localization, reliable release automation, and disciplined Git history.

MacDevClean must earn the user's trust. Before any cleanup, it explains what was found, why the item is considered removable, what will happen if it is removed, whether the action can be recovered, and which tools may need to rebuild or redownload data afterward.

## 2. Success criteria

Version 1.0 is successful when it can:

1. Scan configured project roots and supported global cache locations without blocking the interface.
2. Present reclaimable space by category and individual item.
3. Prevent the cleanup engine from operating on arbitrary or unsafe paths.
4. Move conventional filesystem items to the macOS Trash rather than permanently deleting them.
5. Inspect and clean supported Docker resources with risk-specific safeguards.
6. Analyze large files only inside folders explicitly selected by the user.
7. Preserve exclusions and cleanup history locally.
8. Operate in English and Brazilian Portuguese, including accessibility labels.
9. Build and pass automated tests in CI.
10. Produce a signed and notarized release when Apple signing credentials are available, plus a DMG, GitHub Release, and Homebrew Cask definition.

## 3. Non-goals for version 1.0

- Mac App Store distribution.
- A sandboxed build.
- Root access, administrator authentication, or a privileged helper.
- Automatic or scheduled cleanup.
- Background launch agents or menu-bar-only operation.
- Guaranteed restoration of trashed items.
- Cloud synchronization, user accounts, telemetry, analytics, or a backend service.
- Automatic deletion recommendations for arbitrary personal files.
- Cleaning active Docker containers or selecting Docker volumes by default.
- Supporting macOS versions earlier than macOS 14.

## 4. Reference materials

The repository must include these non-production references:

- `docs/references/macdevclean-ui-reference.png`: the approved visual direction. The image may still show an earlier product name; all production UI must use “MacDevClean.”
- `docs/references/mac_cleanup_reference.sh`: the original shell script, retained only as a behavioral inventory of candidate locations.

The shell script must never be executed by the app, included in the app bundle as an executable cleanup mechanism, or treated as authoritative for security. Native Swift rules and APIs replace its behavior.

## 5. Product principles

### 5.1 Safe by default

- No cleanup item is executed without explicit user action.
- Conventional files and directories go to Trash using macOS APIs.
- High-risk items are never preselected.
- Irreversible operations are visually and textually distinguished from recoverable operations.
- The final review screen is the authoritative confirmation surface.

### 5.2 Explain every action

Every cleanup rule supplies:

- a localized name and description;
- the detected path or external resource identifier;
- its measured size or an explicit “size unavailable” state;
- a risk level;
- the expected consequence, such as dependency reinstallation or slower next build;
- the cleanup mechanism: Trash or irreversible external command.

### 5.3 Local and private

MacDevClean performs all analysis locally. It sends no file names, paths, usage data, or Docker metadata over the network. Network access is not required for scanning or cleanup.

### 5.4 Responsive and cancelable

Scanning and cleanup work runs outside the main actor. Long-running scans expose progress, support cancellation, and publish incremental results without freezing the window.

## 6. Functional scope

### 6.1 Project roots

On first launch, MacDevClean proposes existing conventional roots such as `~/Projects`, `~/Developer`, `~/Code`, and `~/Projetos`. Nothing outside accepted roots is scanned for project artifacts.

The user can add or remove roots with `NSOpenPanel`. Security-scoped bookmarks are not required because the app is distributed outside the sandbox, but selected paths are still persisted as normalized file URLs.

Overlapping roots must be deduplicated so that an item is never measured or displayed twice.

### 6.2 Cleanup categories

Version 1.0 supports these categories:

| Ecosystem | Candidate items | Default risk | Cleanup behavior |
|---|---|---:|---|
| Node.js | `node_modules`, `.turbo`, package-manager caches | Low | Trash |
| Web builds | `dist` | Medium | Trash; separate category with deployment-artifact warning |
| Flutter/Dart | `build`, `.dart_tool`, `.flutter-plugins`, `.flutter-plugins-dependencies`, hosted pub cache | Low | Trash |
| Xcode | DerivedData | Low | Trash |
| Xcode | Archives | Medium | Trash; explain loss of archived builds and symbol bundles |
| Xcode | iOS DeviceSupport | Medium | Trash; explain possible redownload/reprocessing |
| Apple simulators | Simulator caches | Low | Trash |
| CocoaPods | Cache directory | Low | Trash |
| Homebrew | Download cache | Low | Trash |
| Android/Gradle | Gradle caches | Low | Trash |
| Python | pip caches | Low | Trash |
| Rust | Cargo registry and Git caches | Low | Trash |
| Yarn | Yarn cache locations | Low | Trash |
| pnpm | pnpm cache/store locations | Low | Trash |
| Bun | Bun package cache | Low | Trash |

Rule paths must be declared using home-relative or selected-root-relative components, never by concatenating unchecked user input into shell commands.

### 6.3 Docker integration

Docker support is optional at runtime and included in version 1.0. If the Docker CLI is unavailable or the daemon is stopped, the UI shows an actionable unavailable state and all non-Docker features remain usable.

MacDevClean uses `Process` with an executable URL and argument array. It never builds a shell command string. The integration may run only an allowlisted set of read and cleanup operations.

Supported resource classes:

| Resource | Risk | Default selection | Required behavior |
|---|---:|---:|---|
| Build cache | Low | Off | Show estimated space and state that rebuilds may be slower |
| Stopped containers | Low | Off | Show container count and explain that container writable layers are removed |
| Unused images | Medium | Off | Show image count and explain that images may need to be pulled or rebuilt |
| Unused volumes | High | Never selected | Separate section, explicit data-loss warning, second confirmation requiring the user to check an acknowledgment control |

MacDevClean must not stop running containers, remove resources attached to running containers, or execute a broad prune operation whose effects cannot be represented in the review screen.

Docker output parsing must use machine-readable formatting where the CLI supports it. Unsupported or changed output produces an error state rather than a guessed cleanup plan.

### 6.4 Large Files

The Large Files feature is an analysis tool, not an automatic cleanup rule.

- The user explicitly selects one or more folders with `NSOpenPanel`.
- System roots and protected broad locations are rejected.
- The default threshold is 1 GB and can be changed to 100 MB, 500 MB, 1 GB, 5 GB, or 10 GB.
- Results display file name, containing folder, exact size, modification date, and file kind.
- Results can be sorted by size, age, name, or location.
- Available actions are “Reveal in Finder” and “Move to Trash.”
- Nothing is preselected.
- Symbolic links are displayed only as links and are not traversed.

### 6.5 Exclusions

Users can exclude a file, directory, project root, cleanup category, or cleanup rule. An exclusion applies before size calculation and before final cleanup validation.

Exclusions are managed in a dedicated screen and can also be created from an item's context menu. Invalid or missing paths remain visible in settings with a status explaining that they currently do not resolve.

### 6.6 Cleanup history

Each cleanup session records:

- start and completion timestamps;
- selected and completed item counts;
- estimated and actually observed reclaimed bytes when available;
- per-item display name, category, original location or external identifier, cleanup method, risk, result, and localized-safe error code;
- whether the item was moved to Trash or removed irreversibly.

History never stores file contents. “Show in Trash” is offered only when the resulting Trash URL still resolves. MacDevClean does not promise automatic restoration. Docker history explicitly marks operations as irreversible.

History can be cleared by the user after a confirmation. Clearing history does not affect files in Trash.

### 6.7 Settings

Settings include:

- project roots;
- scan-on-launch toggle, off by default;
- large-file threshold;
- exclusions shortcut;
- interface language using system default, English, or Portuguese (Brazil);
- appearance using system, light, or dark;
- history retention: forever, 30 days, or 90 days;
- app version, licenses, privacy statement, and links to project documentation.

## 7. Risk model

`RiskLevel` has exactly three values:

- `low`: regenerable cache or build output with no expected data loss;
- `medium`: regenerable or replaceable content whose removal can affect workflows, archives, or download time;
- `high`: potentially user-authored or otherwise unrecoverable data, including Docker volumes.

Risk must be conveyed through icon, label, color, and explanatory copy. Color alone is insufficient.

Selection policy:

- No results are selected immediately after a scan.
- A user may select low- and medium-risk items from the results screen.
- High-risk items require selection from their expanded detail section.
- Cleanup always proceeds through the review screen.
- A plan containing high-risk or irreversible items requires a second confirmation step.

## 8. Safety invariants

The following are non-negotiable and enforced below the UI layer:

1. The cleanup executor accepts only `ValidatedCleanupItem` values produced by `CleanupPlanValidator`.
2. An item must reference a registered rule or an explicit Large Files result selected by the user.
3. Paths are standardized and symlinks resolved only for validation, never followed during recursive scanning.
4. `/`, `/System`, `/Library`, `/Applications`, `/Users`, the current user's home directory, mounted-volume roots, and configured project roots cannot be cleanup targets as whole directories.
5. A project artifact must remain a descendant of an active configured project root after normalization.
6. A global cache target must equal or remain a descendant of the exact allowlisted location declared by its rule.
7. The target's identity and existence are rechecked immediately before execution to reduce time-of-check/time-of-use risk.
8. Filesystem cleanup uses `FileManager.trashItem(at:resultingItemURL:)`; production code must not call `rm`, `rmdir`, or `removeItem` for user-selected cleanup.
9. Docker execution uses allowlisted executable arguments and never invokes a shell.
10. Partial failure stops only the affected item unless continuing would violate plan consistency.
11. Cancellation stops scheduling new items and records the final state of items already started.

## 9. Architecture

### 9.1 Repository shape

```text
MacDevClean/
├── AGENTS.md
├── CLAUDE.md
├── CURSOR.md
├── .cursor/rules/macdevclean.mdc
├── .github/
│   ├── copilot-instructions.md
│   └── workflows/
├── MacDevClean.xcworkspace
├── MacDevCleanApp/
│   ├── App/
│   ├── Features/
│   ├── DesignSystem/
│   ├── Resources/
│   └── MacDevCleanAppTests/
├── Packages/MacDevCleanCore/
│   ├── Package.swift
│   ├── Sources/
│   │   ├── Domain/
│   │   ├── Scanning/
│   │   ├── Cleanup/
│   │   ├── CleanupRules/
│   │   ├── DockerIntegration/
│   │   └── Persistence/
│   └── Tests/
├── MacDevCleanUITests/
├── docs/
│   ├── adr/
│   ├── references/
│   ├── security/
│   └── superpowers/
├── scripts/
├── Formula/
└── README.md
```

The Xcode application target owns UI composition, macOS lifecycle, entitlements, resources, and dependency construction. `MacDevCleanCore` is a local Swift package divided into focused targets. Dependency direction always points inward toward `Domain`.

### 9.2 Core targets

**Domain** defines immutable value types and protocols: scan roots, cleanup rules, detected items, risk levels, scan progress, cleanup plans, cleanup outcomes, history records, and repository interfaces. It imports Foundation but no SwiftUI or SwiftData.

**Scanning** performs filesystem enumeration, size measurement, deduplication, cancellation, progress reporting, and rule orchestration. It depends on Domain.

**CleanupRules** contains the declarative catalog for supported developer ecosystems. Rules describe detection and consequences; they do not delete anything. It depends on Domain.

**Cleanup** validates plans, enforces path policy, sends filesystem items to Trash, coordinates partial failure, and reports outcomes. It depends on Domain and receives system APIs through protocols.

**DockerIntegration** discovers Docker capability, retrieves machine-readable resource information, parses responses, builds allowlisted operations, and executes approved commands. It depends on Domain and an injected process-running protocol.

**Persistence** implements history, settings, roots, and exclusions with SwiftData. It exposes repositories conforming to Domain protocols and does not leak SwiftData models into feature view models.

### 9.3 App features

Each feature owns its SwiftUI views, observable model, navigation destinations, localized copy keys, previews, and feature-level tests:

- Overview
- Caches
- Cleanup Review
- Docker Details
- Large Files
- History
- Exclusions
- Settings

Observable models are annotated `@MainActor` and use Swift Observation. Services use structured concurrency and return `AsyncSequence` or `async throws` APIs where progressive or one-shot behavior is appropriate. Detached tasks are prohibited unless an architectural decision record justifies them.

### 9.4 Dependency construction

The app creates concrete dependencies in one composition root. Production views receive protocols or feature models; they do not instantiate scanners, repositories, `FileManager`, or `Process` directly.

Tests use temporary directories, in-memory repositories, deterministic clocks, and fake process/trash clients. No automated test operates on real user caches, the actual Trash, or a live Docker daemon unless an opt-in environment flag explicitly enables a separately named integration suite.

## 10. Domain model

The implementation plan must preserve these conceptual interfaces, while allowing namespacing and Sendable refinements:

```swift
enum RiskLevel: String, Codable, Sendable {
    case low, medium, high
}

enum CleanupMethod: Codable, Sendable {
    case trash
    case docker(DockerOperation)
}

struct CleanupCandidate: Identifiable, Sendable {
    let id: UUID
    let ruleID: CleanupRuleID
    let location: CleanupLocation
    let category: CleanupCategory
    let size: ByteCount?
    let risk: RiskLevel
    let method: CleanupMethod
    let consequenceKey: String
}

protocol ScanService: Sendable {
    func scan(_ request: ScanRequest) -> AsyncThrowingStream<ScanEvent, Error>
}

protocol CleanupPlanValidating: Sendable {
    func validate(_ selection: CleanupSelection) async throws -> ValidatedCleanupPlan
}

protocol CleanupExecuting: Sendable {
    func execute(_ plan: ValidatedCleanupPlan) -> AsyncStream<CleanupEvent>
}
```

`ValidatedCleanupItem` and `ValidatedCleanupPlan` initializers must not be publicly available outside the validation boundary. This prevents callers from bypassing policy checks.

## 11. User experience

### 11.1 Window and navigation

The main window uses `NavigationSplitView`, has a minimum size of approximately 1,100 by 720 points, restores its last reasonable size, and remains usable at increased text sizes.

Sidebar destinations:

- Overview
- Caches
- Large Files
- History
- Exclusions
- Settings

### 11.2 Overview

The approved reference image guides, but does not pixel-lock, the Overview screen. It contains:

- “Clean with confidence” heading and concise explanatory copy;
- “Safe cleanup” trust indicator;
- circular reclaimable-space visualization;
- primary “Review cleanup” action;
- top cleanup categories with icon, description, size, and risk;
- safe-by-default, performance-impact, and user-control information cards;
- scan start, progress, cancel, empty, partial-error, and completed states.

The application name is always MacDevClean, regardless of the name shown in the historical reference image.

### 11.3 Caches

The Caches screen supports filtering by ecosystem and risk, sorting by size or name, expanding categories, selecting individual items, revealing paths in Finder, adding exclusions, and opening localized explanations.

### 11.4 Cleanup review

Review is a full navigation destination. It presents grouped selected items, total estimated bytes, cleanup methods, consequences, and recoverability. The primary action uses explicit wording such as “Move 12 items to Trash,” not a vague “Continue.”

Docker operations appear separately. High-risk Docker volume cleanup requires a second screen with an unchecked acknowledgment control. The final button includes “Permanently remove.”

### 11.5 Visual system

The visual language follows native macOS conventions with restrained blue accents, neutral surfaces, semantic system colors, SF Symbols, clear hierarchy, and subtle materials. Risk uses:

- informational/blue and success/green for ordinary guidance;
- warning/amber with an attention icon for medium risk;
- destructive/red with a danger icon and “High risk” text for irreversible operations.

The design supports light mode, dark mode, Increase Contrast, Reduce Transparency, Reduce Motion, keyboard focus, VoiceOver, and localized text expansion. Animations are short and functional; scan progress does not use decorative indefinite motion when Reduce Motion is enabled.

## 12. Localization and accessibility

- Development language is English.
- All user-visible strings use String Catalogs.
- Brazilian Portuguese has complete translations before release.
- Dates, byte counts, pluralization, and lists use locale-aware Foundation formatters.
- No layout assumes English string length.
- Every icon-only control has a localized accessibility label and help text.
- Charts expose equivalent textual summaries.
- Risk is never represented by color alone.
- Primary flows are fully keyboard accessible.

## 13. Error handling

Errors are represented as domain-safe codes with localized presentation. User-facing history must not persist raw shell output containing paths or environment details.

Expected states include:

- permission denied;
- target disappeared between scan and cleanup;
- target changed identity after scan;
- scan canceled;
- item already absent;
- Trash unavailable;
- Docker CLI unavailable;
- Docker daemon unavailable;
- Docker output unsupported;
- Docker operation partially failed;
- storage size unavailable;
- persisted bookmark or path no longer resolves.

An individual failure does not erase successful results. The completion screen summarizes completed, skipped, canceled, and failed items and offers a copyable privacy-safe diagnostic report.

## 14. Persistence and privacy

SwiftData stores settings, project roots, exclusions, and cleanup history in the user's Application Support container. Scan results are transient and are not persisted beyond what is needed for the active review flow.

The app does not collect telemetry. The privacy document states that all scanning and history remain on device. Logs use `Logger` with privacy annotations and do not emit full user paths at public visibility.

## 15. Testing strategy

### 15.1 Unit tests

- Rule catalog detection and consequences.
- Path normalization, descendant validation, protected-root rejection, symlink handling, overlapping-root deduplication, and time-of-check/time-of-use revalidation.
- Byte aggregation and unavailable-size handling.
- Risk and selection policies.
- Docker command allowlist and parsers using captured fixtures.
- Localization key presence for English and Brazilian Portuguese.
- History mapping and retention.

### 15.2 Integration tests

- Synthetic directory trees inside test-owned temporary directories.
- Trash protocol implementations that record requests without touching the user's Trash.
- SwiftData repositories using isolated in-memory containers.
- Fake process execution for Docker success, malformed output, timeout, cancellation, and partial failure.

### 15.3 UI tests

- First launch and root selection.
- Scan, filter, select, review, and simulated Trash flow.
- Docker warning and high-risk acknowledgment.
- Large Files scan and Reveal in Finder affordance using test fixtures.
- History and exclusion management.
- English and Brazilian Portuguese smoke flows.
- Keyboard navigation and critical accessibility identifiers.

### 15.4 Performance tests

Synthetic trees measure enumeration throughput, cancellation latency, UI result batching, and memory growth. The release criterion is that the UI remains responsive while processing at least 100,000 synthetic file entries; the exact elapsed-time baseline is recorded on CI hardware rather than encoded as a hardware-independent promise.

## 16. Agent guidance files

The first implementation milestone creates:

- `AGENTS.md` as the canonical instruction source;
- `CLAUDE.md` and `CURSOR.md` as concise tool-specific entry points;
- `.cursor/rules/macdevclean.mdc` and `.github/copilot-instructions.md` for native tool discovery;
- `CONTRIBUTING.md`, `SECURITY.md`, `CODE_OF_CONDUCT.md`, and repository templates.

These files must agree on:

- Swift 6 and macOS 14;
- TDD and required verification commands;
- prohibition of destructive tests against real user data;
- safety invariants from this specification;
- architectural dependency direction;
- Conventional Commits and branch workflow;
- prohibition of secrets, generated signing credentials, and personal absolute paths in commits.

Adapter files reference `AGENTS.md`, this specification, and the active implementation plan instead of duplicating detailed rules.

## 17. Git workflow

The repository begins on `main`. The implementation agent creates `develop` from `main` after the initial repository policy and planning artifacts are committed.

Feature branches originate from and merge back into `develop`. Planned branch sequence:

1. `feat/project-foundation`
2. `feat/scanning-engine`
3. `feat/cleanup-safety`
4. `feat/docker-integration`
5. `feat/app-shell`
6. `feat/large-files`
7. `feat/history-and-exclusions`
8. `feat/localization-accessibility`
9. `chore/release-pipeline`

Each branch uses TDD, small Conventional Commits, a self-review of the complete diff, and the full relevant test suite before a non-fast-forward merge. Direct feature work on `main` or `develop` is prohibited.

`release/1.0.0` originates from `develop`, receives only release fixes and documentation changes, and merges into `main`. `main` is tagged `v1.0.0`, then merged back into `develop`. Published history is not rewritten.

## 18. Continuous integration and release

Pull request CI performs:

- Swift package tests;
- app unit tests;
- UI smoke tests;
- release build without signing;
- static formatting validation;
- checks that localization keys exist in both languages;
- checks that committed files contain no obvious secrets or machine-specific absolute paths.

Release automation produces an archived `.app`, signs it with Developer ID Application when credentials are configured, notarizes and staples it, creates a DMG, calculates checksums, and uploads artifacts to a GitHub Release.

The project maintains a third-party Homebrew tap containing a Cask that downloads the notarized DMG. The intended installation command is:

```bash
brew install --cask <github-owner>/macdevclean/macdevclean
```

The actual GitHub owner is supplied when the repository is created and is release configuration, not an architectural constant. Official `homebrew/cask` submission may be attempted after stable public releases and user adoption; it is not required for 1.0.

Signing and notarization steps skip with a clear message on forks or local environments without secrets. Build and test validation must remain fully available without paid credentials.

## 19. Documentation and portfolio presentation

The repository includes:

- an English `README.md` with screenshots, value proposition, supported cleanup rules, safety model, architecture summary, setup, tests, installation, and roadmap;
- `README.pt-BR.md` with equivalent user-facing content;
- architecture decision records for modular packaging, non-sandboxed distribution, Trash-first cleanup, Docker process isolation, and local-only privacy;
- `SECURITY.md` describing responsible disclosure and the cleanup threat model;
- a short demo GIF or video recorded from fixture data rather than personal paths;
- a release changelog;
- badges only for meaningful automated checks.

Screenshots and demo data must not expose personal user names, home paths, project names, or Docker resource names.

## 20. Acceptance criteria for 1.0

1. A fresh clone builds on a supported Xcode installation with deployment target macOS 14.
2. The app launches into a localized and accessible first-run experience.
3. Scanning a synthetic project root returns correct, deduplicated candidates and byte totals.
4. Canceling a large scan returns the interface to a usable state without leaking tasks.
5. Attempting to construct a cleanup plan for a protected root fails below the UI layer.
6. Approved filesystem items are sent through the Trash abstraction and recorded in history.
7. A changed, missing, or symlink-swapped target is rejected at execution time.
8. Docker absence and daemon failure do not affect filesystem scanning.
9. Docker volumes cannot be cleaned without explicit selection and second confirmation.
10. Large Files scans only user-selected folders and never preselects results.
11. English and Brazilian Portuguese critical UI flows pass automated smoke tests.
12. VoiceOver labels and keyboard navigation cover every primary action.
13. CI builds, tests, and validates formatting on every feature merge.
14. Release automation can create an unsigned local artifact and a signed/notarized artifact when secrets are present.
15. Installation through the project's Homebrew Cask installs MacDevClean into `/Applications`.

## 21. Future work

The following may be considered after 1.0 and must not delay the initial release:

- scheduled scans and macOS notifications;
- menu bar status;
- additional package managers and IDEs;
- user-defined cleanup rules with a constrained declarative format;
- duplicate-file analysis;
- official Homebrew Cask submission;
- optional Sparkle-based updates if Homebrew and manual-download update behavior can remain unambiguous.
