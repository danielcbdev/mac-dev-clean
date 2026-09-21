# Planning review and coverage

This is a review of documentation, not a claim that MacDevClean has been implemented or its tests passed.

## Deliverables

Nine sequential implementation plans contain 25 tasks with file ownership, interface boundaries, behavioral test examples, red/green commands, commits and exit criteria. The execution guide defines bootstrap and merge lifecycle. Interface contracts resolve cross-target symbols. The original approved specification is retained with a separate technical-clarifications companion.

The reference image was opened and inspected during planning. Its sidebar, split dashboard, ring summary, category list and three information cards are described in plan 05. Misleading performance/safety wording in the generated reference is explicitly corrected. The base shell script is optional reference only; it was unavailable at its original path when the bundle was assembled.

## Spec coverage

| Approved acceptance criterion | Owning tasks and evidence to collect during implementation |
|---|---|
| 1 Fresh clone builds, macOS 14 | 01.2–3; 09.1 and minimum-OS runtime checklist |
| 2 Localized accessible first-run | 05.1; 08.1–2 |
| 3 Correct deduplicated candidates/totals | 02.1–3 |
| 4 Cancel large scan cleanly | 02.3; 08.3 |
| 5 Protected-root rejection below UI | 02.1; 03.1 |
| 6 Trash API and history | 03.2–3; 07.1–2 |
| 7 Identity/missing/symlink changes | 03.2; residual path-race limit documented |
| 8 Missing Docker doesn't break scans | 04.1; 05.1 |
| 9 Volume selection + second confirmation | 04.3; 05.3 |
| 10 Explicit-root large files | 06.1–2 |
| 11 English and pt-BR smoke tests | 08.1–2 |
| 12 Keyboard/VoiceOver labels | 08.2 |
| 13 CI gate before integrations | 01.3; execution guide |
| 14 Local and signed artifacts | 09.1–2 |
| 15 Cask installs desktop app | 09.3; real remote install pending until authorized publication |

Remaining spec features are allocated as follows: global cache catalog 02.2; selection/risk 03.1 and 05.2–3; error export 03.3/08.3; roots/preferences/appearance/retention 07.2; local-only policy 04.1/07.2; agent instructions and templates 01.1; release flow 09.3; architecture and ADRs 01.3/03.3/04.1/07.1; screenshot/demo docs 08.2/09.3. Future work remains outside the version scope.

## Issues corrected during self-review

- Domain history protocols referenced types previously scheduled too late: declarations now appear in foundation.
- Public validated tokens could not live in Domain with internal constructors and be created by another target: validation types stay inside Cleanup.
- Bare directory names risk deleting authored content: rule evidence and Git status checks are mandatory for ambiguous artifacts.
- Directory exclusions only filtering parent names could delete excluded descendants: policy tests block ancestor cleanup.
- Changes to rule evidence after scanning were initially underspecified: RuleEvidenceChecking is injected into both validator and executor.
- In-memory history in an intermediate UI milestone could lose real cleanup records: live app cleanup stays disabled until durable journal composition.
- App tests and preview dependencies could leak test targets into the shipping app: app-local DEBUG preview ports and separate package test support are specified.
- “Bytes moved” and “bytes freed” were conflated: the contracts and UI distinguish them.
- Docker stopped-container and archive risk was understated: technical clarifications promote them to high risk.
- Public release could appear successful with missing credentials: public mode now fails and local unsigned output is labeled development-only.
- Cask file location and future owner/checksum values: generation occurs under Casks using real validated release inputs.
- Git main bootstrap versus always-releasable claim: the initial documentation commit is explicitly a bootstrap exception.
- Test examples and later task symbols were reconciled with the shared interface contracts; test helper additions belong to their owner tasks.

## Document checks

Mechanical validation checks nine plan headers, five review-focus entries per plan, task Files/Interfaces sections, checkbox steps, balanced code fences, resolvable internal Markdown links and missing-detail markers. The validator lives in the preparation workspace, not in the future application.

Test examples are design specifications for future XCTest suites, not a compiled application. External SDK versions and signing/hosting configuration must be verified by the implementing agent against the selected environment.

## Execution handoff

Review the plans and technical clarifications before starting the implementation. The supplied START-HERE prompt selects native task-by-task execution, suitable for a single agent in the new folder. A subagent-per-task workflow is optional if the owner chooses it; no independent review is claimed in this planning package.

No product code, Git repository, feature branch, remote, release, certificate, installation or cleanup was created or performed while writing these plans.

