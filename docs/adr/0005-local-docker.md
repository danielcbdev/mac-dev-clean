# ADR 0005: Local Docker only, through a typed process port

- **Status:** Accepted
- **Date:** 2026-09-21
- **Plan:** 04 Docker integration, Task 1

> Numbering note: plan 04 refers to this decision as "0004". That number was
> taken by [ADR 0004](0004-trash-first.md) during plan 03, so this is 0005.

## Context

Docker removals are irreversible. There is no Trash for a volume, an image or a
container's writable layer. A mistake here is not recoverable, so the integration
has to be narrow in a way the filesystem side does not.

Two failure modes matter more than the rest:

1. **Cleaning the wrong machine.** A Docker *context* is a label. The user can
   point `desktop-linux` at a production server over SSH and the name will not
   change. A tool that trusts the name will happily destroy data on a host
   nobody was looking at.
2. **Shell injection through a resource name.** Container names, image tags and
   volume names come from projects, and projects come from the internet.

## Decision

**Only a local Unix socket, explicitly selected.** `validateEndpoint` accepts
`unix://` and nothing else. `ssh://`, `tcp://`, `https://`, `npipe://` and `fd://`
are refused, including `tcp://127.0.0.1`, because a local TCP endpoint is still
not the socket the user picked. The endpoint is settled from `docker context
inspect` **before the daemon is contacted at all**, so a remote context receives
no requests whatsoever — a test asserts exactly one command was issued in that
case.

**Identity, not names.** The capability fingerprint binds the endpoint path, the
daemon's own `ID` and the builder. Re-pointing a context at another machine
changes the fingerprint even though the name is identical, and every write
revalidates against it.

**Nothing is inherited.** Commands run with an environment built from nothing —
`HOME` (context definitions live under it) and `LC_ALL=C`. `DOCKER_HOST`,
`DOCKER_CONTEXT`, `BUILDX_BUILDER` and `DOCKER_CONFIG` from the user's session
cannot reach the child.

**No shell, and no interpreter.** `LocalProcessRunner` takes an executable URL
and an argument array. Before launching it refuses shells, `env`, `sudo`, `su`,
`osascript` and language interpreters outright, and it never consults `PATH` —
a test passes `printf`, which really is on `PATH`, and requires the launch to
fail.

**The executable is found in known places only.** An explicit user choice, then
`/Applications/Docker.app/Contents/Resources/bin/docker`, `/usr/local/bin/docker`,
`/opt/homebrew/bin/docker`. No writable project directory is searched and no
login shell is run to ask where `docker` lives. The installation symlink is
resolved so the app reports the real binary.

**Bounded, and always finishing.** 8 MiB of combined output, a 10-second read
deadline and a 60-second write deadline. Both pipes are drained concurrently,
because draining one to the end before starting the other deadlocks as soon as
the second fills its buffer — there is a test for that. Exceeding a bound
terminates the child rather than waiting or growing.

**Docker is never started.** No `docker desktop start`, no builder bootstrap, no
pull, no run. If Docker is not running, the feature reports itself unavailable
and every filesystem feature carries on unaffected.

## Consequences

Users with a remote or SSH context get an explicit "not supported" state rather
than a silent partial capability. That is the right trade: the alternative is a
tool that might delete a colleague's database.

A builder with any remote node becomes inspection-only, and build-cache cleanup
alone is disabled — the rest of the integration keeps working. The same applies
when Buildx cannot report usage as JSON: without precise per-record filtering,
that one feature is switched off rather than approximated.

`LocalProcessRunner` uses two lock-guarded `@unchecked Sendable` helpers, for the
output sink and for reaching the child from the cancellation handler. Every
stored property is read and written only under the lock, which is what makes the
annotation sound rather than a suppression.

**No test in this repository has contacted a Docker daemon.** Every Docker test
answers from a recorded script. Testing against a live daemon requires the
owner's explicit authorisation and disposable resources, and has not been done.
