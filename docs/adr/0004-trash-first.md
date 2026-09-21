# ADR 0004: Trash-first cleanup, with no deletion path at all

- **Status:** Accepted
- **Date:** 2026-09-21
- **Plan:** 03 cleanup safety, Task 3

> Numbering note: plan 03 refers to this decision as "0003". That number was
> already taken by [ADR 0003](0003-git-evidence-adapter.md), written during plan
> 02, so this decision is recorded as 0004. Nothing else changed.

## Context

A disk-cleanup tool's worst outcome is destroying something irreplaceable. The
specification requires filesystem items to go to the macOS Trash rather than
being deleted, and the risk model assumes the user will sometimes be wrong about
what they selected.

The tempting design is "Trash, and fall back to removal if the Trash is
unavailable". Fallbacks like that are how a safety property quietly stops being
one: the fallback fires exactly in the unusual situations where the user is
least able to recover.

## Decision

**Filesystem cleanup calls `FileManager.trashItem(at:resultingItemURL:)` and
nothing else.** There is no fallback. The production code path contains no
`removeItem`, no `unlink`, no `rmdir`, and no command that empties the Trash.

If the Trash is unavailable, the item stays where it is and the failure is
reported. The app also never offers to empty the Trash — that is Finder's job,
and keeping it there means reclaiming space is always a separate, deliberate act
by the user.

`scripts/verify.sh` runs the whole suite on every integration, and the
`Cleanup` target's tests assert the no-fallback behaviour directly: with the
Trash failing, the fixture is still on disk afterwards.

## Consequences

**Space is not freed by cleanup.** On the same volume a trashed item's data
stays on that volume. Everything the app says has to respect this: it reports
**bytes moved to Trash** and, separately, an **observed free-space delta**, and
never adds them up or calls the first the second. After a cleanup the app says
"Moved to Trash. Empty Trash in Finder to reclaim space." and offers to open the
Trash.

**The observed delta is an observation, not proof.** Other processes, APFS
clones, snapshots, hard links and Docker's virtual machine all move that number.
A negative delta is reported as measured rather than clamped to zero, because
clamping would be inventing a result.

**Recovery is likely, not guaranteed.** The Trash is a much better default than
deletion, but it is not a backup: items can be evicted, the volume can fill, and
"Put Back" can fail. The app never promises restoration.

**Docker is the honest exception.** There is no Trash for a Docker volume, image
or container layer. Those removals are final, are labelled irreversible, require
an explicit acknowledgment, and are reported separately from anything that went
to the Trash.

**The result URL can be missing.** `trashItem` reports where the item landed,
and that name can differ from the original. If the move succeeds but no URL
comes back, the item **has moved**: the outcome is recorded as `indeterminate`,
its bytes are not counted as moved, and the move is never repeated to tidy up
the record. Guessing in the other direction would move a file twice.

**Rejected alternative.** A "secure delete" or "empty Trash after cleanup"
option was rejected outright for 1.0. Both would convert a recoverable mistake
into an unrecoverable one, which is the opposite of what this product is for.
