# Verification — plan 09, distribution

- **Date:** 2026-09-21
- **Branch:** `chore/release-pipeline`
- **Toolchain:** Xcode 27.0 (27A266a); Apple Swift 6.4; macOS 27.0 (26A428); arm64

**Development is complete. Publication has not started.** Those are two
different claims and this document keeps them apart.

## Gate result

```text
$ MACDEVCLEAN_SKIP_UI_TESTS=1 bash scripts/verify.sh
exit status: 0
==> verify.sh: all checks that ran passed — UI tests NOT RUN
```

| Check | Result |
|---|---|
| `swift test --package-path Packages/MacDevCleanCore` | **Pass** — 232 tests, 0 failures |
| App unit tests, Debug | **Pass** — 46 tests, 0 failures |
| **UI tests** | **NOT RUN** — 21 written; the XCUITest gate is unavailable here |
| Release build, unsigned | **Pass** |
| `scripts/check-token-access.sh` | **Pass** |
| Localization checker and fixtures | **Pass** — 232 keys, both languages |
| **Release script contracts** | **Pass** — 66 assertions |
| Policy checker and fixtures | **Pass** |
| `scripts/lint.sh` | **Pass** |
| `git diff --check` | **Pass** |
| Remote CI | **Not run** — no push authorized |

Total XCTest cases run: **278**, 0 failures.

## The local artifact exists and was measured

```bash
bash scripts/build-local.sh --version 1.0.0 --output dist/local
bash scripts/verify-artifact.sh --app dist/local/MacDevClean.app --mode unsigned
bash scripts/package-dmg.sh --app dist/local/MacDevClean.app \
    --output dist/MacDevClean-1.0.0-unsigned.dmg
```

All three exited 0.

| Fact | Value |
|---|---|
| App | `dist/local/MacDevClean.app`, 8.3 MB |
| Binary | `Mach-O universal (x86_64 arm64)` |
| Signature | `adhoc, linker-signed` |
| Minimum system version | 14.0 |
| Disk image | 3,082,529 bytes |
| SHA-256 | `120ccb600f345c8c398402fcabc9eed6b728b06984af506ba0d34bf3001fa79f` |

`verify-artifact.sh` **failed the first time**, correctly: the bundle declared
no application icon. `scripts/make-appicon.swift` now draws one — a storage
stack whose top layer has been cleared — and the rebuilt bundle passes.

## What the contract tests actually prove

They run every release script against fixture executables passed by explicit
environment variables. **No real build, no real signing, no credentials, and no
PATH spoofing**, which would leak into everything else the session runs.

**Packaging.** A missing app is refused. An existing output is refused rather
than overwritten, and the existing file is verified untouched afterwards. A path
containing spaces works. A failing build produces no app and leaves none behind.
A version that is not `major.minor.patch` — including `1.0.0; touch /tmp/pwned`
— never reaches `xcodebuild`.

**Verification.** A single-architecture binary, a wrong minimum system version,
a `CFBundleExecutable` that does not resolve, a bundle carrying a `.p12`, and a
bundle carrying fixture resources are each refused. **Ad-hoc signing is refused
as a Developer ID signature**, which is the mistake this script exists to
prevent; an unsigned app fails signed verification; a Developer ID authority
passes.

**Credentials.** A public preflight in an `env -i` environment fails and names
the missing variables. A secret present in the environment never appears in the
output. An owner containing `../../etc` is refused.

**Signing and notarization.** With no credentials, nothing is signed and no
artifact appears. A failing `codesign` stops the release, with no artifact. A
notarization returning `Invalid` stops the release, with no artifact. Only an
`Accepted` status, parsed out of the JSON rather than inferred from an exit
code, produces an image.

**The workflow.** No `pull_request_target`, and no pull-request trigger at all,
so code from a fork cannot reach a job holding credentials. Credentials sit
behind a named environment. `contents: read` at the top; `contents: write`
appears only in the publishing job, which runs last.

**The cask.** Rendered from synthetic inputs — `test-owner`, `test-repo`,
`1.0.0`, 64 `a` characters — it is valid Ruby, interpolates each field exactly,
and contains **no `zap`, no `uninstall`, no `preflight`, no `postflight`, and no
reference to Trash, Caches or Library**. An owner carrying a shell fragment is
refused and nothing is written. A non-semantic version, a short digest and an
uppercase digest are each refused. A final assertion checks that
**`Casks/macdevclean.rb` is not committed**, because it must be generated from a
real release.

## The offline claim is now checkable

Earlier milestones recorded that the product is offline but noted the check was
implicit: nothing imported a networking API, and nothing asserted that. Two
facts now back it.

- `scripts/check-policy.sh` fails if production Swift uses `Network`,
  `CFNetwork`, `NetworkExtension`, `URLSession`, `NSURLConnection` or
  `CFSocket`, and `scripts/tests/fixtures/policy-networking` must be rejected.
- `otool -L` on the built universal binary lists no networking library:

  ```text
  $ otool -L dist/local/MacDevClean.app/Contents/MacOS/MacDevClean | grep -i network
  (no output)
  ```

Neither proves the application makes no connection at runtime — only a traced
run would — but a networking call can no longer be added without failing the
gate.

## The performance job

`.github/workflows/performance.yml` runs `ScanPerformanceTests` on manual
dispatch only, records the runner's CPU, core count, memory and toolchain
alongside the results, and uploads both. It asserts no wall-clock threshold: a
number from a hosted runner is not comparable with a number from a developer's
machine. **It has never run**, because no push has been authorized.

## What was deliberately not done

- **The application was not launched.** The Release composition would write
  `~/Library/Application Support/MacDevClean/store.sqlite` onto the verifying
  machine. First launch is a manual check, not a silent side effect of
  verification.
- **No cask was generated.** There is no release URL and no published checksum,
  and a cask built from invented inputs fails at install time for everyone who
  trusted it.
- **No licence was chosen**, so there is no `LICENSE` file. That decision
  belongs to the owner.
- **Nothing was pushed, published, signed or tagged.** `origin` exists; no push
  was authorized. No Apple credential was created, requested or used.
- **`v1.0.0` was not created.** Most of
  [docs/release/checklist.md](../release/checklist.md) is unchecked, and a tag
  is a statement that those gates passed.

## Known omissions and limitations

- **UI tests have not run**, so no screenshot, VoiceOver pass or live
  performance measurement exists.
- **The signed pipeline has never run against Apple.** Its failure modes are
  tested with fakes; its success path has never touched a real notary service.
  A fake that returns `Accepted` proves the script's control flow, not that
  Apple would accept this application.
- **Every pinned action SHA needs re-verification** against GitHub before a
  real release. `release.yml` reuses the revisions pinned in `ci.yml` by an
  earlier milestone.
- **The build came from the working tree**, not a fresh clone.
- **macOS 14 and Intel hardware were never available.** The deployment target
  and the `x86_64` slice are compilation facts.
- **No independent review took place.**
