## Summary

<!-- What changed and why. Link the plan and task, for example
     docs/superpowers/plans/2026-09-21-02-scanning.md Task 1. -->

## Verification

Paste the commands you actually ran and their real exit status. Do not claim a
check you did not run — record it as not run instead.

```text
$ bash scripts/verify.sh
# exit status:
```

- [ ] `swift test --package-path Packages/MacDevCleanCore`
- [ ] App unit tests (`xcodebuild ... test`, Debug)
- [ ] Release build without signing
- [ ] `bash scripts/lint.sh`
- [ ] `git diff --check`
- [ ] UI tests — or recorded as a missing gate with the reason

Toolchain used (`xcodebuild -version`, `swift --version`):

```text
```

## Safety review

- [ ] No new code path deletes files outside `FileManager.trashItem(at:)`
- [ ] Cleanup still accepts only validated items built inside `Cleanup`
- [ ] Path policy, protected roots and exclusions still enforced below the UI
- [ ] Docker commands remain allowlisted argument arrays, never shell strings
- [ ] No test touches real user caches, the real Trash or a live Docker daemon
- [ ] No secrets, certificates, keychains or personal absolute paths committed

## User-visible changes

- [ ] Not applicable
- [ ] Screenshots attached, taken from fixture data only (no personal paths,
      project names or Docker resource names)
- [ ] English and Brazilian Portuguese strings both present
- [ ] Accessibility labels and keyboard access covered

## Known omissions

<!-- Anything deliberately left out, and why. -->
