# MacDevClean — GitHub Copilot instructions

Read AGENTS.md and the active plan before editing.

`AGENTS.md` is the canonical engineering contract. Execution order and the
branch lifecycle are defined in
`docs/superpowers/plans/2026-09-21-00-execution.md`. Current state is tracked in
`docs/progress.md`.

Key constraints: Swift 6 language mode, macOS 14 deployment target, native
SwiftUI, package dependencies pointing inward toward `Domain`, Trash-only
filesystem cleanup through validated plans, allowlisted Docker arguments with no
shell, tests on owned temporary fixtures with fake destructive adapters.

Do not duplicate the rules here. If guidance conflicts, `AGENTS.md` wins.
