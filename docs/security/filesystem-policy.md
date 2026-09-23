# Filesystem policy

How MacDevClean decides that a path may be cleaned, and what it refuses to
decide. This describes enforced behaviour in `Scanning/PathPolicy.swift`,
`Scanning/LocalFileSystem.swift` and `Scanning/ReadOnlyGitClient.swift`, each
covered by tests in `Tests/ScanningTests`.

## What the user interface may ask for

The interface can display candidates and submit **identifiers** from a
registered scan snapshot. It cannot submit a path. `InMemoryCandidateStore`
resolves an identifier back to the candidate, its evidence and the policy
revision the scan ran under. A candidate value invented by a caller reaches
nothing.

## The order of checks

`PathPolicy.check(_:ruleID:context:)` runs these in order, and the first failure
wins. Order matters, because the error the user sees should name the real
reason.

1. **Is the rule registered?** The identifier must be a known project rule, a
   global cache rule with a registered root in the current context, or the Large
   Files rule. Anything else is `unsupported`. A caller cannot invent a rule name
   to widen its own scope.
2. **What is actually on disk?** The target is read with `lstat` semantics.
   Missing is `missing`. A symbolic link is `symbolicLink` and is never
   followed or cleaned. The root of another mounted volume is `protectedPath`.
   A cloud placeholder is `unsupported`, because measuring it would make the
   provider download it.
3. **Is the location protected?** See the table below.
4. **Is it in scope?** See "Scope" below.
5. **Is the path between the root and the target sound?** Every directory
   between the allowed root and the target must exist, be a directory, not be a
   mount point, and be on the same device as the target.
6. **Is anything excluded?** See "Exclusions" below.

## Protected locations

| Location | Protection |
|---|---|
| `/System`, `/Library`, `/Applications` | The directory **and every descendant** |
| `/`, `/Users`, `/Volumes`, `/private`, `/var` | The directory itself |
| The user's home | The directory itself; descendants may still be eligible |
| A mounted volume root, `/Volumes/<name>` | The directory itself |
| A configured project root | The directory itself **and every ancestor above it** |

`~/Library` is not `/Library`: after canonicalisation it is a descendant of the
home directory, which is how `~/Library/Caches/Homebrew` can be a candidate
while `/Library` can never be.

## Scope

- **Project rules** — the target must be *strictly inside* an active configured
  project root. The root itself is never a candidate.
- **Global cache rules** — the target must equal, or be inside, one of the exact
  locations that rule registered in the current safety context. A global rule
  cannot reach a path some other rule registered.
- **Large Files** — the target must be strictly inside a folder the user
  explicitly chose for that feature. Project roots grant no Large Files scope and
  Large Files roots grant no project scope.

External volumes selected by the user are read-only in version 1.0. Their scan
results explain that cross-volume cleanup is unsupported.

## Path comparison

Comparison is **component-wise**, never `path.hasPrefix(root.path)`. A string
prefix cannot tell `/work/application` from something inside `/work/app`; a
component comparison can, and a test pins that case.

Before comparing, a path is standardised and its symbolic links resolved. That
also collapses the `/var`, `/tmp` and `/etc` aliases onto their `/private`
originals, so two spellings of one location compare equal. Resolution is for
comparison only — recursive scanning never follows a link.

Case handling follows the volume: the policy asks the volume whether it
distinguishes case, and when it cannot be asked it assumes case-insensitive,
because treating more paths as equal protects more rather than less.

Volume identity is checked with the device number from `lstat`, so two paths on
different volumes never contain one another regardless of how they read.

## Exclusions

`matches(_:exclusion:)` is true in three situations, and the third is the one
that is easy to get wrong:

1. the exclusion is the candidate;
2. the exclusion is an **ancestor** of the candidate;
3. the exclusion is a **descendant** of the candidate.

Case 3 blocks cleaning the ancestor as a whole, because moving the ancestor to
the Trash would take the excluded child with it. The scanner skips the ancestor
rather than quietly trashing the excluded child.

Rule exclusions are applied here. Category exclusions are applied by the callers
that know a candidate's category — the scanner and the cleanup validator —
because `check` receives a rule identifier, not a category.

## Asking Git instead of guessing

A directory named `dist` or `build` may be generated output or may be authored
content somebody committed. The name alone never decides. `ReadOnlyGitClient`
answers two questions, and if it cannot answer, the artifact is skipped:

- a fixed absolute executable at `/usr/bin/git`, never a `PATH` lookup;
- separate literal arguments, never an interpolated command string, never a
  shell;
- an environment built from nothing: system and global configuration disabled so
  no user-controlled setting can point Git at an external filter or program;
- `GIT_OPTIONAL_LOCKS=0` and `--no-optional-locks`, so reading never writes to
  the user's repository;
- `GIT_LITERAL_PATHSPECS=1` for `ls-files`, so a path containing `*` or `:` is a
  path rather than a pattern;
- `check-ignore` cannot accept literal pathspec magic — Git rejects it outright —
  so it runs without that variable, receives the path on stdin rather than on
  the command line, and its answer is accepted only when the pathname Git echoes
  back is byte-identical to the one that was sent;
- bounded output and a hard timeout; a timeout, an oversized response, an
  unexpected exit status or a path outside the repository all fail closed.

Project code is never executed. Package scripts do not run, JavaScript
configuration is not evaluated, and repository hooks never fire.

## Reading evidence files

An evidence file — `package.json`, `pubspec.yaml`, `tsconfig.json` — is read
through `readPrefix`, which refuses anything larger than 256 KiB or not a
regular file. Oversized input is reported as unsupported rather than parsed
hopefully.

## Residual risk, stated plainly

`FileManager.trashItem(at:)` is a path-based API, not an atomic
descriptor-relative operation. Identity checks and ancestor revalidation
immediately before the side effect narrow the time-of-check / time-of-use
window, but they cannot mathematically eliminate a malicious concurrent
replacement of a path component. The app fails closed on any observed change.
This limitation is real and is not claimed away.
