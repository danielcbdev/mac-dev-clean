# Contributing to MacDevClean

Read [AGENTS.md](AGENTS.md) before your first change. It is the canonical
engineering contract and it wins over any other document in this repository.

## Requirements

- macOS 14 or newer to run the app; the deployment target is macOS 14.0.
- Xcode 16 or newer with the Swift 6 language mode. The exact toolchain this
  repository was validated against is recorded in
  [docs/adr/0002-toolchain.md](docs/adr/0002-toolchain.md).
- No paid Apple account is needed to build, run or test. Signing and
  notarization are release-only concerns.

## Verification commands

Run the full gate before opening a pull request or merging a branch locally:

```bash
bash scripts/verify.sh
```

It runs, in order:

```bash
swift test --package-path Packages/MacDevCleanCore
xcodebuild -workspace MacDevClean.xcworkspace -scheme MacDevClean -destination 'platform=macOS' -derivedDataPath .build/xcode test CODE_SIGNING_ALLOWED=NO
xcodebuild -workspace MacDevClean.xcworkspace -scheme MacDevClean -configuration Release -destination 'platform=macOS' -derivedDataPath .build/release build CODE_SIGNING_ALLOWED=NO
bash scripts/lint.sh
git diff --check
```

UI tests need a logged-in macOS session. If UI test infrastructure is
unavailable, record it as a missing gate — never as a pass.

## Test policy

Tests run against synthetic fixtures the test itself owns, inside temporary
directories, using fake Trash and fake Docker adapters.

Automated tests must never touch your real caches, the real Trash, or a live
Docker daemon. A separately named opt-in integration suite may do so only behind
an explicit environment flag.

## Workflow

- Branch from `develop`. Never commit feature work directly to `main` or
  `develop`.
- Branch names follow the plan sequence, for example `feat/scanning-engine`.
- Write a failing test first, then make it pass. No skipped tests or empty
  assertions count as done.
- Use [Conventional Commits](https://www.conventionalcommits.org/): `feat:`,
  `fix:`, `docs:`, `test:`, `refactor:`, `chore:`, `ci:`.
- Keep commits small and focused on one change.
- Review the complete branch diff yourself before merging:
  `git diff develop...HEAD`.
- Merge with `git merge --no-ff`, then re-run the gate.
- Published history is never rewritten.

## Pull requests

Fill in [the template](.github/pull_request_template.md). Include the actual
commands you ran and their real exit status. Include before/after screenshots
for user-visible UI changes, taken from fixture data — never from personal
paths, project names or Docker resource names.

## Never commit

Secrets, API tokens, signing certificates, `.p12` or `.p8` files, keychains,
provisioning profiles, personal absolute paths, or machine-specific
configuration.

## Reporting

Security issues: see [SECURITY.md](SECURITY.md). Behavior expectations: see
[CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).
