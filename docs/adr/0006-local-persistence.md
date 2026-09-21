# ADR 0006: Local SwiftData storage, and never destroying it to recover

- **Status:** Accepted
- **Date:** 2026-09-21
- **Plan:** 07 persistence, Task 1

> Numbering note: plan 07 refers to this decision as "0005". That number was
> taken by [ADR 0005](0005-local-docker.md) during plan 04, so this is 0006.

## Context

MacDevClean needs to remember four things between launches: preferences, project
roots, exclusions, and what it did. The fourth is not a convenience. A tool that
moves a developer's files and then forgets it did so leaves the user with no way
to find out what happened.

Everything stays on the device. There is no account, no server and no sync, so
the only question is which local store.

## Decision

**SwiftData, in the user's Application Support container**, at
`Application Support/MacDevClean/store.sqlite`. One versioned schema, `SchemaV1`,
and a migration plan listing that one version with **no invented future stages** —
a stage appears when a schema change actually happens, together with the test
that proves data survives it.

The whole store is confined to one model actor. No `ModelContext` crosses an
isolation boundary; only `Codable`, `Sendable` snapshots do.

Stored rows hold identifiers, dates, raw enumeration strings and bounded encoded
payloads. **Semantic values, never translated strings**: the language preference
is `portugueseBrazil`, so changing the interface language cannot corrupt the
setting that chose it. Path exclusions keep their exact case, because a
case-sensitive volume would treat a folded path as a different place.

### A corrupt store is never erased or recreated

If the store cannot be opened, `make` throws `storeUnavailable` and **leaves the
file exactly as it is**. A test writes garbage to the store path, asserts the
open fails, and then asserts the file is still byte-for-byte what it was.

The obvious "recovery" — delete it and start fresh — would destroy the record of
everything the app had already done, at precisely the moment the user most needs
it. The application degrades instead: it still scans and explains, cleanup is
disabled, and the interface says why.

### Durability is what enables cleanup

`AppDependencies.live()` sets `cleanupEnabled` from whether durable storage
opened. In-memory storage reports `isDurable == false` and never satisfies it.
A cleanup whose record vanishes on quit is not offered at all.

### A corrupt *record* does not hide a session

If one row's payload will not decode, the row stays on disk and the entry
appears in history marked unreadable. One bad record cannot make a whole session
disappear.

### Interrupted sessions stay uncertain

`recoverInterruptedSessions` turns any `pending` row into `indeterminate` with
the code `session.interrupted`. It touches no file and issues no Docker command.
The interface shows it as "Outcome unknown" — never as a failure, and never with
a retry, because retrying would act on something whose state nobody knows.

Beginning the same session identifier twice is refused rather than allowed to
reset progress already recorded.

### Retention deletes records, never files

Retention removes only **completed** sessions older than the cutoff. A session
still in progress, or one whose outcome is unknown, is kept however old it is.
Clearing history removes records and leaves preferences, roots and exclusions
untouched. Neither has any filesystem effect: emptying the Trash is Finder's job.

## Consequences

The app requires no network and no permissions beyond its own container.

Migrations are now a real obligation. Changing a model means adding a
`MigrationStage` and a test that writes with the old schema and reads with the
new one. The empty `stages` list is a promise that no schema change has happened
yet, not an oversight.

A user who moves or removes the store loses their history and settings. That is
acceptable: it is their file, in a documented location, and nothing else depends
on it.
