# Security policy

## Supported scope

Security support applies to the most recent released version of MacDevClean on
macOS 14 or newer. Earlier macOS versions and forks are out of scope.

## Reporting a vulnerability

Report privately through GitHub's private vulnerability reporting on this
repository (Security → Report a vulnerability), if the maintainer has enabled it
for the repository. If private reporting is not available, open an issue that
describes the impact and asks for a private channel, without publishing a
working exploit or user paths.

No other reporting contact is published here. Do not assume an email address or
security team exists.

Please include the affected version, the macOS version, reproduction steps
against synthetic fixtures, and the observed versus expected behavior. Do not
include real personal paths, project names or Docker resource names.

## Cleanup threat model

MacDevClean moves developer build artifacts and caches to the Trash and removes
explicitly reviewed Docker resources. The damage from a defect is data loss, so
the following boundaries are enforced below the user interface.

### Trust boundaries

- The user interface is untrusted input. It may present candidates, but it can
  only submit **candidate identifiers** from a registered scan snapshot. It can
  never submit a raw path for cleanup.
- The cleanup executor accepts only `ValidatedCleanupItem` values built by
  `CleanupPlanValidator`. Those types have internal initializers and no public
  decoding, so no caller outside the validation boundary can forge one.
- Both validation and execution re-verify rule evidence and path policy, so a
  stale scan cannot authorize a target that has since changed meaning.

### Enforced invariants

- Protected roots — `/`, `/System`, `/Library`, `/Applications`, `/Users`, the
  user's home, mounted-volume roots and configured project roots — are rejected
  as whole-directory targets, including their descendants where the
  specification requires it.
- Project artifacts must remain descendants of an active configured project
  root after normalization. Global cache targets must equal or descend from the
  exact allowlisted location their rule declares.
- Path comparison is component-wise and volume-aware. String prefix matching is
  insufficient. `/var` and `/private/var` aliases are canonicalized first.
- Scanning does not walk into mount points, `.git`, app bundles, cloud
  placeholders or symlinked directories. Symlinks are never cleanup candidates.
- An exclusion inside a proposed directory blocks cleaning that ancestor as a
  whole. A root exclusion blocks its descendants.
- A directory name alone never establishes disposability. Ambiguous artifacts
  require rule evidence — a readable manifest and a read-only Git index check.
  If Git metadata cannot be read, the artifact is skipped.
- Filesystem cleanup uses `FileManager.trashItem(at:resultingItemURL:)`. The
  production code path contains no `rm`, `rmdir` or `removeItem` for
  user-selected cleanup, and the app never empties the Trash.
- Docker commands are built as an executable URL plus an argument array. No
  shell string is ever constructed. Only an allowlisted operation set runs, on
  an explicitly selected local Unix-socket context whose daemon identity is
  revalidated before each write. Resources are removed by reviewed identifier;
  broad prune is not used.
- No network access is required or performed for scanning or cleanup. Local
  Docker IPC is the only external connection.

### Residual risks, stated honestly

- `FileManager.trashItem(at:)` is a path-based API, not an atomic
  descriptor-relative operation. Identity checks with `lstat` and ancestor
  revalidation immediately before the side effect reduce time-of-check /
  time-of-use exposure, but they cannot mathematically eliminate a malicious
  concurrent replacement of a path component. The app fails closed when it
  observes a change.
- Moving items to the Trash does not free disk space. Space is reclaimed only
  when the user empties the Trash in Finder.
- Trashed items are not guaranteed to be restorable. Docker removals are
  irreversible and are labeled as such.
- Observed free-space deltas are observations, not causal proof. APFS clones,
  snapshots, hard links, other processes and Docker's virtual machine all affect
  them.

## Privacy

All scanning, cleanup and history stay on the device. MacDevClean has no
telemetry, analytics, accounts or backend. History never stores file contents,
and user-facing diagnostics never persist raw command output containing paths or
environment details. Logs use `Logger` privacy annotations and do not emit full
user paths at public visibility.
