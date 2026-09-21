# MacDevClean agent contract
Read START-HERE.md, docs/superpowers/specs/2026-09-21-macdevclean-design.md,
docs/superpowers/specs/2026-09-21-implementation-clarifications.md,
docs/superpowers/specs/2026-09-21-interface-contracts.md and the active plan.
Use Swift 6, macOS 14, native SwiftUI and inward package dependencies.
Keep cleanup authority in Cleanup; never trust UI-provided raw paths.
Use test-owned temporary fixtures, fake Trash and fake Docker adapters.
Do not run the reference script or clean the user's machine for testing.
Write behavioral red/green tests for scanner, policy, executor and parsers.
Run scripts/verify.sh and review the full branch diff before local merges.
Use main -> develop -> feat/*, Conventional Commits and --no-ff merges.
Record actual evidence and task progress; never invent test passes or reviews.
No remote publication, credentials use, or real-data cleanup without authority.
Preserve user changes and never rewrite published history.

## Plans

Plans live in `docs/superpowers/plans/`. Start with
`docs/superpowers/plans/2026-09-21-00-execution.md`, which defines the ordered
deliverables, branch lifecycle, verification commands and resume procedure.

## Safety invariants

These are enforced below the UI layer and are non-negotiable:

1. The cleanup executor accepts only `ValidatedCleanupItem` values produced by
   `CleanupPlanValidator`. Validated types have internal initializers.
2. Every item references a registered rule or an explicit Large Files result the
   user selected.
3. Paths are standardized and symlinks resolved only for validation, never
   followed during recursive scanning.
4. `/`, `/System`, `/Library`, `/Applications`, `/Users`, the user's home,
   mounted-volume roots and configured project roots are never cleanup targets
   as whole directories. Protection extends to descendants of system roots.
5. A project artifact must stay a descendant of an active configured root.
6. A global cache target must equal or descend from the exact allowlisted
   location declared by its rule.
7. Identity and existence are rechecked immediately before execution.
8. Filesystem cleanup uses `FileManager.trashItem(at:resultingItemURL:)`.
   Production code must not call `rm`, `rmdir` or `removeItem` for cleanup.
9. Docker execution uses allowlisted executable arguments and never a shell.
10. Partial failure stops only the affected item.
11. Cancellation stops scheduling new items and records started items.

## Architecture

Dependency direction points inward toward `Domain`.

| Target | Production imports |
|---|---|
| Domain | Foundation |
| CleanupRules | Domain, CryptoKit |
| Scanning | Domain, CleanupRules |
| Cleanup | Domain |
| DockerIntegration | Domain |
| Persistence | Domain, SwiftData |
| MacDevCleanApp | package products, SwiftUI, AppKit, OSLog |
| TestSupport | Domain, CleanupRules, Scanning, Cleanup (test consumers only) |

`Domain` never imports another target. No core target imports the app.
`TestSupport` is a test-support target and never a production dependency.

## Truthful reporting

Moving to Trash does not free space. Report bytes moved to Trash, Docker
reported reclaim and observed free-space delta separately, and never present a
sum moved as space freed. Never claim a general performance improvement.

## Verification

```bash
bash scripts/verify.sh
```

It runs the package tests, the Debug app and UI tests, an unsigned Release
build, `scripts/lint.sh` and `git diff --check`, and exits 0 only if every check
passed. The Debug test action is signed ad hoc on purpose; see
`docs/adr/0002-toolchain.md`.

Record the real command, exit status, toolchain, date and known omissions in
`docs/verification/<milestone>.md`. A check that did not run is recorded as not
run, never as a pass.

## Prohibited in commits

Secrets, signing credentials, `.p12`/`.p8` files, keychains, personal absolute
paths, and machine-specific configuration.
