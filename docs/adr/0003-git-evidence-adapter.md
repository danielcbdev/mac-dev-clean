# ADR 0003: Ask Git for evidence, through a read-only adapter

- **Status:** Accepted
- **Date:** 2026-09-21
- **Plan:** 02 scanning, Task 1

## Context

Some artifact directories are unambiguous: `node_modules` beside a readable
`package.json` is installed content. Others are not. A directory named `dist`
or `build` may be generated output, or may be authored content that somebody
committed. Deleting the second kind destroys work that has no other copy.

The name alone cannot distinguish them. The repository can: content Git tracks
is authored, and content Git ignores is generated.

## Decision

Ambiguous artifacts require evidence from Git, obtained through a narrow
read-only adapter, and are **skipped** when that evidence cannot be obtained.

The adapter runs a fixed absolute `/usr/bin/git` with separate literal
arguments and no shell, in an environment built from nothing — system and
global configuration disabled, so no user-controlled setting can redirect Git at
an external filter or program. Reading never writes: `GIT_OPTIONAL_LOCKS=0` and
`--no-optional-locks`. Output is bounded and the call has a hard timeout. A
timeout, an oversized response, an unexpected exit status, or a path outside the
repository all fail closed.

Project code is never executed to discover output paths. No package script runs,
no JavaScript configuration is evaluated, no hook fires.

## Two corrections to the documented commands

The implementation clarifications specify `ls-files -z` and `check-ignore -z`
"with literal pathspecs". Neither spelling works as written against the Git on
the tested toolchain, and both were corrected while preserving the intent.

**`check-ignore -z` requires `--stdin`.** Observed:

```text
fatal: -z only makes sense with --stdin
```

The adapter now sends the path NUL-terminated on standard input. This is also
the stricter arrangement, because the path never appears on the command line.

**`check-ignore` cannot accept literal pathspec magic.** Observed with
`GIT_LITERAL_PATHSPECS=1`:

```text
fatal: dist: pathspec magic not supported by this command: 'literal'
```

`ls-files` accepts it and keeps it. `check-ignore` runs without it, and the
weaker guarantee is replaced by verification rather than by trust: Git echoes
the pathname it judged, and the adapter accepts the verdict only when that
pathname is byte-identical to the one it sent. If Git ever answered about a
different path — the failure mode literal pathspecs were meant to prevent — the
answer is discarded and the artifact is treated as not ignored, which is the
conservative direction.

Both corrections are pinned by tests:
`testReadsIgnoreRules` and
`testAnIgnoreAnswerIsAcceptedOnlyForTheExactPathAsked`, the latter using a
directory whose name contains a wildcard character.

## Consequences

A repository that cannot be read yields no cleanup candidate for an ambiguous
directory. That is a deliberate false negative: the tool offers less rather than
risking authored content.

Users without Git installed lose only the ambiguous categories. Unambiguous
artifacts — `node_modules`, `.dart_tool`, registered global caches — do not
depend on this adapter.

The adapter is the only place in the product that runs an external program other
than the Docker integration, and like that integration it builds an argument
array and never a command string.
