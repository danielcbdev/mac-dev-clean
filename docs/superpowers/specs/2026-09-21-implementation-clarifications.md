# Implementation clarifications

These engineering clarifications accompany the approved product spec. They resolve inconsistencies found while planning; they do not introduce new product subsystems. If a product choice here is rejected, revise the corresponding plan before execution.

## Space accounting and truthful copy

Moving files to Trash on the same volume normally keeps their data on that volume. Never report the sum moved as space freed. Track logical bytes, allocated bytes where available, bytes moved to Trash, Docker-reported reclaim, and observed free-space delta separately. Free-space deltas are observations, not causal proof: other processes, APFS clones, snapshots, hard links and Docker's VM affect them.

After a filesystem cleanup say “Moved to Trash. Empty Trash in Finder to reclaim space.” Provide “Open Trash”; do not empty it from this app. The circular chart reports “Potential cleanup” with a tooltip explaining estimated storage; its denominator is the sum of known candidate category sizes, not the entire disk. Unknown sizes are visible and excluded from totals. Filesystem and Docker sizes have separate subtotals rather than one misleading precise total.

The mockup's “Reclaim performance” claim becomes “Know the impact”: rebuilding caches may slow the next build. Never claim a general speed improvement from cleanup.

## Resource risks

The earlier table labeled stopped containers low-risk; writable layers may contain unique data. Classify stopped containers HIGH and require the same irreversible confirmation as volumes. Unused local images have no guaranteed remote replacement; classify as MEDIUM with a clear lost-local-build warning, never call them universally recoverable. Xcode Archives HIGH: they may include irreplaceable binaries/dSYMs. Arbitrary large files HIGH. This tightens, rather than relaxes, the approved explicit-risk UX.

## Selection, exclusions and filesystem boundaries

Folder name alone does not establish disposability. Associate Node artifacts with a readable package.json and Flutter artifacts with pubspec.yaml containing Flutter evidence. A dist directory needs tool configuration/output evidence and no tracked Git content; otherwise show as unsupported/manual review, not an executable cleanup candidate. Never execute package scripts, evaluate JS configuration or run project hooks to discover output paths. Swift-native Git-index inspection is not necessary: an allowlisted read-only git client may use ls-files -z and check-ignore -z with literal pathspecs, no shell, hooks, config-driven external filters or untrusted executable lookup. If Git metadata cannot be checked, skip ambiguous artifacts.

An exclusion inside a proposed directory blocks cleaning that ancestor as a whole. A root exclusion blocks its descendants. Component-wise comparison, volume identity and filesystem case behavior matter; string prefix matching is insufficient. Do not walk into mount points, .git, app bundles, cloud placeholders or symlink directories. Skip symlink candidates for cleanup. Large Files may show them informationally without an action.

Registered global locations are eligible only within the current user's actual home and outside protected subtrees. Protect descendants of system roots, not merely the root directory itself. Canonicalize /var and /private/var aliases before comparisons. Project roots and their ancestors cannot become cleanup items. User-selected external root access is read-only in v1; its scan results explain that cross-volume cleanup is unsupported. Global overrides are accepted only after explicit user selection and normal path-policy validation.

FileManager Trash is a path-based API, not an atomic descriptor-relative removal API. lstat identity and ancestor revalidation mitigate races but cannot mathematically eliminate malicious concurrent replacements. Record this residual risk in the threat model; do not claim guaranteed race immunity. Fail closed on observed changes, and stop new items on cancellation.

## Module ownership

Six local package targets: Domain, CleanupRules, Scanning, Cleanup, DockerIntegration, Persistence. Domain owns plain values and I/O protocols. Cleanup owns ValidatedCleanupPlan, validator and executor protocols plus their implementations; internal initializers stay in that target. Putting the token in Domain with internal init would prevent the Cleanup target from constructing it. No public raw-token factory.

Fixture support is a test-support target, not a production dependency. The app composes services explicitly. SwiftData model contexts remain actor-isolated; only Codable Sendable snapshots cross boundaries.

## Docker local-only behavior

Accept only explicitly selected local Docker Desktop contexts whose endpoint is a Unix socket and whose daemon identity matches the inspected daemon. Reject ssh/tcp contexts, remote builders, swarm/plugin volumes and unknown volume drivers. Pass the chosen --context and builder to every command, revalidate endpoint and daemon before each write, and do not inherit DOCKER_HOST or other endpoint overrides. Do not start Docker Desktop or a builder automatically.

Remove container/image/volume resources by reviewed IDs, never global prune. For build cache use a capability-tested Buildx ID filter per record, bound to the reviewed builder; omit --all. Unknown capabilities disable only build-cache cleanup with a useful explanation. Commands and compatibility fixtures are specified in plan 04.

Local Docker IPC is the only external service connection in the app; scanning does not contact internet endpoints.

## Repository and distribution details

Use Casks/macdevclean.rb (not Formula/) for the desktop application. Use a native Xcode project plus checked-in workspace and a local Swift package. Commit a shared MacDevClean scheme. Xcode 16 is the minimum toolchain for Swift 6; choose a specific available supported Xcode build at foundation time, record it, and pin CI to that tested version. Do not pretend to have tested every Xcode 16+ release.

The first main commit is a bootstrap baseline, not a releasable application. Thereafter main contains validated release milestones. Use actual Git history and local merge records, not invented remote PRs. No remote is needed to complete development. No final version tag or public “released” claim until the release checklist is satisfied.

A missing signing secret allows local unsigned builds but must fail a requested public production-release job. Never quietly publish an unsigned artifact as the signed release. Homebrew installation testing and publication require authorized release URLs.

## Sources checked for planning

- [Apple FileManager Trash API](https://developer.apple.com/documentation/foundation/filemanager/trashitem(at:resultingitemurl:)): use returned Trash URL; names can change.
- [Docker container removal](https://docs.docker.com/reference/cli/docker/container/rm/): do not use force or volume-removal flags.
- [Docker image removal](https://docs.docker.com/reference/cli/docker/image/rm/): use no-prune to avoid unreviewed parent deletion.
- [Docker volume removal](https://docs.docker.com/reference/cli/docker/volume/rm/): skip in-use volumes; never force.
- [Buildx disk usage](https://docs.docker.com/reference/cli/docker/buildx/du/): JSON lines and shared/reclaimable fields.
- [Buildx prune](https://docs.docker.com/reference/cli/docker/buildx/prune/): targeted id filters and builder selection.
- [Apple notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).
- [Homebrew Cask cookbook](https://docs.brew.sh/Cask-Cookbook).

