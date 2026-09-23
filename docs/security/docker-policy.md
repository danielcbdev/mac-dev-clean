# Docker policy

Docker removals cannot be undone. There is no Trash for a volume, an image or a
container's writable layer, so this integration is narrower than the filesystem
side in every direction.

Companion documents: [threat-model.md](threat-model.md),
[ADR 0005](../adr/0005-local-docker.md).

## The complete set of commands

This app can issue these and nothing else. Every token below is a separate
process argument; no command string is ever built and no shell is involved.

### Reads

```text
docker context inspect CONTEXT
docker --context CONTEXT version --format {{json .}}
docker --context CONTEXT info --format {{json .}}
docker --context CONTEXT container ls --all --no-trunc --format {{json .}}
docker --context CONTEXT container inspect --size ID
docker --context CONTEXT image ls --no-trunc --format {{json .}}
docker --context CONTEXT image inspect ID
docker --context CONTEXT volume ls --format {{json .}}
docker --context CONTEXT volume inspect NAME
docker --context CONTEXT buildx inspect BUILDER
docker --context CONTEXT buildx du --builder BUILDER --format=json
```

### Writes

```text
docker --context CONTEXT container rm FULL_ID
docker --context CONTEXT image rm --no-prune FULL_ID
docker --context CONTEXT volume rm REVIEWED_NAME
docker --context CONTEXT buildx prune --builder BUILDER \
    --filter id=RECORD_ID --filter inuse=false --force
```

### What is deliberately absent

| Not used | Why |
|---|---|
| `system prune`, `builder prune`, `container prune`, `image prune`, `volume prune` | Their effects cannot be shown on a review screen before they happen. |
| `--all` on any prune | It reaches records outside the reviewed set. |
| `--force` on container removal | Forcing stops a running container. |
| `--force` on image removal | Forcing breaks tag references nobody reviewed. |
| `--volumes` on container removal | It destroys data belonging to a different resource kind. |
| `docker desktop start`, builder bootstrap, `pull`, `run` | This app inspects and removes. It never starts anything. |

`buildx prune` is the one command carrying `--force`, purely to suppress its
interactive prompt after the app's own confirmation, and it is always pinned to a
single record id and to `inuse=false`.

## Which daemon, and how that is enforced

Only a **local Unix socket**, selected explicitly. `ssh://`, `tcp://` — including
`tcp://127.0.0.1` — `https://`, `npipe://` and `fd://` are all refused.

The endpoint is settled from `docker context inspect` **before the daemon is
contacted**, so a remote context receives no requests at all. A test asserts that
exactly one command is issued in that case.

The capability fingerprint binds the **endpoint path, the daemon's own `ID` and
the builder** — never the context name, which the user can repoint at another
machine without changing a character of it. Every write revalidates against that
fingerprint first.

Commands run with an environment built from nothing: `HOME`, because context
definitions live under it, and `LC_ALL=C`. `DOCKER_HOST`, `DOCKER_CONTEXT`,
`BUILDX_BUILDER` and `DOCKER_CONFIG` from the user's session cannot reach a child
process.

The executable is found only at an explicit user choice,
`/Applications/Docker.app/Contents/Resources/bin/docker`, `/usr/local/bin/docker`
or `/opt/homebrew/bin/docker`. No writable project directory is searched, `PATH`
is never consulted, and no login shell is run to ask where `docker` lives.

## Which resources are eligible, and their risk

| Resource | Eligible when | Risk | What the user loses |
|---|---|---:|---|
| Build cache record | `Reclaimable` **and** not `Mutable` | Low | The next build is slower. |
| Stopped container | Not running | **High** | Its writable layer, which can hold data that exists nowhere else. |
| Unused image | Referenced by **no** container, running or stopped | Medium | It must be pulled again — and a locally built image cannot be pulled at all. |
| Unused volume | Referenced by **no** container, and on the built-in `local` driver | **High** | Everything in it. This is where databases live. |

**"Not running" never means "not in use".** Images and volumes are compared
against every container the daemon lists, stopped ones included. A stopped
container still holds its image and still holds its volumes, and tests pin both
cases.

Plugin and cluster volume drivers are inspection-only: their storage may be
somewhere this app knows nothing about.

Stopped containers and volumes are both classified **high**, which tightens the
approved risk table rather than relaxing it. That is the correction recorded in
the implementation clarifications, and it means both require the same explicit,
irreversible acknowledgment.

## Sizes, and what is not claimed

- **Volume sizes are unknown** unless the daemon reports them in `UsageData`. No
  volume is mounted and the Docker disk image is never read to work one out.
  Docker's `-1` placeholder is unknown, not zero.
- **Image sizes share layers.** Removing two images does not free the sum of
  their sizes. Totals are kept per resource kind and are never added into one
  confident number.
- **Shared build-cache records** are excluded from any exact reclaimable total,
  because their bytes belong to more than one record.
- **Docker reclaim is reported separately** from filesystem bytes moved to the
  Trash. They are different things and are never summed.

## Unrecognised means refused

A missing field, a changed shape or a number that will not fit produces an error
or an explicit unknown — never an assumption of eligibility:

- a missing `Reclaimable` means **not** reclaimable;
- a missing `Mutable` means **assume mutable**, so the record stays ineligible;
- a missing `Shared` means **assume shared**, so it stays out of exact totals;
- a missing container `State` is `unknown`, and `unknown` is not "stopped";
- a missing `Running` flag in an inspection is treated as **running**;
- a string is not accepted where a boolean is expected;
- a human-readable size such as `1.09GB` is never turned into an exact number;
- negative and oversized values are unknown, with a reason attached.

## Identifier validation

Container names, image tags and volume names come from projects, and projects
come from the internet. Every identifier that could reach a command line must
match its exact documented shape:

| Kind | Required shape |
|---|---|
| Container | 64 lowercase hexadecimal characters |
| Image | `sha256:` followed by 64 lowercase hexadecimal characters |
| Volume | ASCII letter or digit, then letters, digits, `_`, `.`, `-` |
| Build cache | An alphanumeric token |
| Context / builder | Letter or digit first, then letters, digits, `_`, `.`, `-` |

Anything empty, option-like (`-f`, `--all`), punctuated or carrying control
characters is refused before it can become an argument. It is not escaped and
hoped about — it never reaches the command.

## Before and after each write

Every removal is revalidated immediately beforehand: the fingerprint still
matches, the resource still exists, a container is still stopped, an image is
still referenced by nothing, a volume is still attached to nothing, a cache
record is still reclaimable. A multi-tag image is **refused**, because a
non-forcing removal cannot address it without affecting references nobody
reviewed.

A volume that becomes unused *because an earlier item in the same plan was
removed* is not cleaned. It was not eligible in the reviewed snapshot, and the
review is what the user agreed to.

**A timed-out write may already have taken effect.** The app asks once, and
classifies the answer three ways: gone (the write landed, and is not repeated),
still there (a failure), or unanswerable (`indeterminate`). "I could not find
out" is never recorded as "it is gone", and a Docker write is never retried
blindly — a retry could remove something recreated in the meantime.

## Testing

**No test in this repository has contacted a Docker daemon.** Every Docker test
answers from a recorded script through `RecordingProcessRunner`, and the fixtures
contain no real project, image, path or account name.

Testing against a live daemon requires the repository owner's explicit
authorisation and disposable resources created for that purpose. It has not been
done, and nothing in the automated suite can do it.

## Sources

- [docker container rm](https://docs.docker.com/reference/cli/docker/container/rm/) — no force, no volume removal.
- [docker image rm](https://docs.docker.com/reference/cli/docker/image/rm/) — `--no-prune` to avoid unreviewed parent deletion.
- [docker volume rm](https://docs.docker.com/reference/cli/docker/volume/rm/) — in-use volumes are skipped, never forced.
- [docker buildx du](https://docs.docker.com/reference/cli/docker/buildx/du/) — JSON lines with shared and reclaimable fields.
- [docker buildx prune](https://docs.docker.com/reference/cli/docker/buildx/prune/) — targeted id filters and builder selection.
