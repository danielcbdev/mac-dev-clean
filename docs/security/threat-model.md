# Cleanup threat model

MacDevClean moves a developer's files to the Trash and removes Docker
resources. The damage from a defect is data loss, so this document states what
the design defends against, how, and — just as importantly — what it does not
defend against.

Companion: [filesystem-policy.md](filesystem-policy.md) covers path rules in
detail.

## What is being protected

Work that exists in one place only: uncommitted source, an archive with the
only symbol bundle for a shipped build, a Docker volume holding a database, a
patched file inside an installed dependency.

## Assets, adversaries and assumptions

The app runs as the user, unsandboxed, with no privileged helper and no
administrator prompt. It can therefore touch anything the user could delete in
Finder, and nothing more.

The realistic threats are not a remote attacker. They are, in order of
likelihood:

1. **A bug in this program** that classifies authored content as disposable.
2. **A race**: the filesystem changes between the scan, the confirmation and the
   side effect — usually because a build, an installer or an editor is running.
3. **A confused-deputy path**: some layer persuading the cleanup engine to act
   on a path nobody reviewed.
4. **A local attacker or hostile repository** planting symlinks or swapping
   directory components to redirect a removal.

There is no network attack surface: scanning and cleanup contact nothing. Local
Docker IPC is the only external connection the app makes.

## Defences

### Authority cannot be minted

The interface submits identifiers, never paths. Everything about a candidate —
its location, rule, risk and method — is read back from the registered scan
snapshot, so a caller cannot present an arbitrary path as a low-risk cache.

`ValidatedCleanupItem` and `ValidatedCleanupPlan` have initialisers internal to
the `Cleanup` target and no `Codable` conformance. Code outside that target,
including the application itself, cannot construct one, so the executor's input
can only have come from the validator. `scripts/check-token-access.sh` compiles
a fixture that tries anyway and requires it to fail as inaccessible, with a
second fixture proving the public surface still works.

### Everything is checked twice, late

The scanner checks policy. The validator checks it again against the *live*
safety context. The executor checks it a third time immediately before each
side effect. Between those moments an exclusion may have been added, a manifest
edited, a directory replaced.

Each check covers: protected locations, scope containment, the whole ancestor
chain, symbolic links, mount points, cloud placeholders, path and category and
rule exclusions, `lstat` identity against what the scan recorded, and rule
evidence re-derived from the project as it is now.

### Plans are short-lived and single use

A plan expires 60 seconds after validation and carries the policy revision it
was built under. A review screen left open all afternoon cannot be confirmed
against a world that has moved on, and a changed revision invalidates it
outright. The executor consumes a plan exactly once: confirming twice does not
act twice.

### Removal is Trash-only

Filesystem cleanup calls `FileManager.trashItem(at:resultingItemURL:)` and
nothing else. There is no fallback to `removeItem`, no `unlink`, and no command
that empties the Trash. If the Trash is unavailable the item stays where it is.

### Docker writes are narrow

Resources are removed by reviewed identifier on an explicitly selected local
Unix-socket context, with the daemon identity revalidated before each write.
Commands are an executable URL plus an argument array — never a shell string —
and broad prune is not used.

### Failure is contained

One failure stops one item. The journal is written ahead of any side effect: if
the intent cannot be recorded, nothing moves. If recording fails *after*
something moved, the session stops scheduling and the item is marked unrecorded
— the move is never repeated to tidy up history. Pending rows found after a
restart become `indeterminate`, never "probably succeeded".

## What this does not defend against

These are real limitations, stated plainly rather than argued away.

### The path race cannot be closed

`FileManager.trashItem(at:)` takes a **path**, not a file descriptor. Between
the moment the executor confirms a path's identity and the moment the Trash API
resolves that same path, a sufficiently determined local process can replace a
component of it.

Identity checks with `lstat`, full ancestor revalidation and failing closed on
any observed change narrow that window to something very small. They do not
eliminate it, and no amount of checking with a path-based API can. **This
program does not offer atomic protection against a concurrent local attacker,
and does not claim to.**

The practical consequence for an ordinary user is different and milder: a build
or installer running during cleanup can change a directory under the app's feet,
and the app will refuse that item rather than act on it.

### Trashed items are not guaranteed to be recoverable

The Trash is a much better default than deletion, but it is not a backup. Items
can be evicted, the volume can fill, and "Put Back" can fail. MacDevClean never
promises restoration.

### Docker removals cannot be undone

There is no Trash for a Docker volume, image or container layer. A removal is
final, is labelled as such, and requires an explicit acknowledgment. A write
interrupted part way may leave an outcome nobody can determine; the app records
that honestly and does not claim to have rolled anything back.

### Moving to the Trash does not free space

On the same volume, a trashed item's data stays on that volume. The app reports
**bytes moved to Trash** and, separately, an **observed free-space delta**. The
second is an observation, not causal proof: other processes, APFS clones,
snapshots, hard links and Docker's virtual machine all move that number. A
negative delta is reported as measured and never clamped to zero.

### Detection is heuristic, and deliberately timid

A directory is judged by evidence — a readable manifest, a Git answer — not by
its name. When the evidence is missing or Git cannot be reached, the artifact is
skipped. That produces false negatives on purpose: the tool offers less rather
than risking authored content.

### Concurrent builds are not coordinated

MacDevClean does not lock anything and cannot know a build is running. Cleaning
a cache mid-build may make that build fail. Nothing is corrupted, but the build
will have to run again.

## Privacy

All analysis stays on the device. There is no telemetry, no analytics, no
account and no backend. History never stores file contents. The copyable
diagnostic report contains rule identifiers, counts, error codes and the app
version only — never an original path, a Trash URL, a Docker resource name or
command output. Logs use `Logger` privacy annotations and do not emit full user
paths at public visibility.
