# Distribution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce an installable local desktop app and a verifiable signed distribution workflow with Homebrew Cask.

**Architecture:** Packaging consumes an already-tested universal app; protected release jobs sign and notarize before any publication. Credentials stay outside the repository.

**Tech Stack:** xcodebuild, codesign, notarytool, stapler, hdiutil, GitHub Actions, Homebrew Cask.

**Spec:** [Approved specification](../specs/2026-09-21-macdevclean-design.md); [technical clarifications](../specs/2026-09-21-implementation-clarifications.md).

## Global Constraints

- Product: MacDevClean; desktop application from the first runnable milestone.
- Swift 6 language mode; deployment target macOS 14; Xcode 16 or newer, with the exact tested Xcode build recorded.
- UI: English and Brazilian Portuguese; source, commits, technical documentation: English.
- SwiftUI, Observation, structured Swift Concurrency, Foundation, SwiftData and XCTest.
- No production runtime dependencies outside Apple frameworks; any build tooling dependency requires an ADR.
- No sandbox, privileged helper, administrator prompt, telemetry, server, scheduled deletion or background agent.
- Filesystem cleanup is Trash-only; no permanent filesystem deletion or empty-Trash command.
- Docker writes require a confirmed immutable selection, local endpoint verification and typed allowlisted commands.
- Tests operate on owned synthetic fixtures and fake destructive adapters; never on user caches, real Trash or existing Docker resources.
- Follow the approved spec plus the documented technical clarifications in docs/superpowers/specs/2026-09-21-implementation-clarifications.md.
- Do not publish, create remote repositories or upload artifacts without explicit authorization; local branches, commits and merges are authorized.

## Review Focus

- A path containing spaces must package without quoting errors: Task 1.
- A missing credential must fail public release rather than publish unsigned: Task 2.
- Notarization rejection must never produce a successful release: Task 2.
- A cask uninstall must not remove development data/history: Task 3.
- A claimed minimum OS/architecture must be distinguished from actual runtime test coverage: Task 3.

---

## Scope and files

Prerequisites: plans 01–08. Branch: chore/release-pipeline.

Create:
- scripts/{build-local,package-dmg,release-preflight,sign-notarize,verify-artifact,render-cask}.sh.
- scripts/tests/release-contract-tests.sh and fixture executables.
- .github/workflows/{release,performance}.yml.
- Casks/macdevclean.rb (generated after a real release URL/checksum is known; do not commit a fake runnable definition).
- docs/release/{configuration,checklist,homebrew-tap,manual-install}.md.
- docs/verification/09-distribution.md.
- README.md, README.pt-BR.md, CHANGELOG.md and docs/demo/.
Modify project asset catalog for AppIcon, app version/build settings and CI artifact packaging.

### Task 1: Local universal app and DMG

**Files:** scripts/{build-local,package-dmg,verify-artifact}.sh, scripts/tests/release-contract-tests.sh, MacDevClean.xcodeproj/project.pbxproj, docs/release/manual-install.md.

**Interfaces:** build-local.sh --version <semver> --output <directory> builds an unsigned app and returns nonzero on error. package-dmg.sh --app <app-path> --output <dmg-path> creates a drag-to-Applications image. verify-artifact.sh --app <path> --mode unsigned|signed checks the appropriate promises, never treats ad-hoc signing as Developer ID.

- [ ] Before implementation add release-contract-tests using test-owned directories and fake xcodebuild/hdiutil/codesign through explicit injected tool paths in test scripts, not PATH spoofing of the real user's shell. Cases: missing app fails; existing output refuses overwrite; path with spaces works; failed builder stops packaging; success output includes executable and Info.plist; archive excludes private fixtures/signing files.
```bash
if bash scripts/package-dmg.sh --app "$fixture_root/missing.app" --output "$fixture_root/out.dmg"; then
  echo "Expected missing app failure" >&2
  exit 1
fi
```
fixture_root is allocated/validated by the test runner via mktemp -d; cleanup targets only that owned path.
- [ ] Run `bash scripts/tests/release-contract-tests.sh` red (specific missing behavior), then implement build using:
```bash
xcodebuild -workspace MacDevClean.xcworkspace -scheme MacDevClean -configuration Release -destination 'generic/platform=macOS' -derivedDataPath .build/package ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO MACOSX_DEPLOYMENT_TARGET=14.0 CODE_SIGNING_ALLOWED=NO build
```
Pass validated MARKETING_VERSION from --version and monotonic build number, not arbitrary shell fragments. Stage app with ditto into unique temporary folder; do not alter /Applications or overwrite existing user assets.
- [ ] package-dmg creates an Applications symlink in staging and invokes:
```bash
ln -s /Applications "$stage_dir/Applications"
hdiutil create -volname MacDevClean -srcfolder "$stage_dir" -ov -format UDZO "$new_dmg_path"
```
new_dmg_path must be a newly allocated output under requested directory after refusing an existing final path; -ov applies only to this validated staging path. Validate payload paths before output handoff.
- [ ] verify-artifact checks CFBundleExecutable resolves, minimum OS=14.0, arm64+x86_64 via lipo, correct app display name, version, app icon and no DEBUG fixture resource/flag functionality. Launch unsigned app locally from its staged folder (user authorization only if it would run real scan automatically; launch default is idle). Do not move to /Applications without permission. Test bundled smoke scenario in dedicated Debug artifact, not a hidden production fixture flag.
- [ ] Write manual local install instructions clearly labeled unsigned development artifact and OS prompts; do not recommend disabling Gatekeeper globally. Run tests/build/packaging checks, record SHA-256 and commit:
```bash
git add scripts docs MacDevCleanApp MacDevClean.xcodeproj
git commit -m "build: package universal macOS app and local DMG"
```

### Task 2: Signed release pipeline and strict credential boundaries

**Files:** scripts/{release-preflight,sign-notarize}.sh, scripts/tests/release-contract-tests.sh, .github/workflows/release.yml, docs/release/configuration.md.

**Interfaces:** release-preflight.sh --mode unsigned|public reports configuration missing; public mode fails if any required value is absent. sign-notarize.sh --app <path> --output <dmg> consumes an already-tested app and release configuration, returns only a verified distribution artifact.

Release inputs:
| Name | Source | Meaning |
|---|---|---|
| MACDEVCLEAN_RELEASE_OWNER | workflow variable | actual GitHub owner |
| MACDEVCLEAN_RELEASE_REPO | workflow variable | actual repository name |
| MACDEVCLEAN_BUNDLE_ID | workflow variable | developer-owned reverse-DNS identifier |
| APPLE_TEAM_ID | protected environment variable | actual team ID |
| APPLE_CERTIFICATE_P12_BASE64 | protected secret | Developer ID Application cert/private key |
| APPLE_CERTIFICATE_PASSWORD | protected secret | P12 import password |
| APPLE_API_KEY_ID | protected secret | notarization App Store Connect key ID |
| APPLE_API_ISSUER_ID | protected secret | notarization issuer UUID |
| APPLE_API_PRIVATE_KEY | protected secret | notarization .p8 content |

No real values appear in source. If unavailable, complete unsigned/local deliverables and document pending items. Do not buy membership or create credentials.

- [ ] Add test that public preflight with empty test environment exits nonzero listing variable NAMES only; unsigned preflight passes. Add signing failure -> no upload; notarization rejected -> no public artifact; fork PR -> signing job never runs. Test scripts with fake commands, never actual secrets.
- [ ] Implement protected release workflow using workflow_dispatch for authorized release candidate and tag trigger only after checklist. Read-only permissions for tests; contents:write only in final authorized publishing job. Use protected GitHub environment with required approval for credentials. No pull_request_target or execution of untrusted PR code with secrets. Pin action revisions, verify actual SHAs at implementation time.
- [ ] Sign nested Mach-O/framework components first if present, then app with hardened runtime and timestamp; avoid blindly signing --deep. Use an ephemeral keychain with scoped search-list changes restored on EXIT. Never disable library validation unless a reviewed dependency requires it; current app needs no such exception. Archive for notarization, submit and verify:
```bash
codesign --force --options runtime --timestamp --sign "$signing_identity" "$app_path"
ditto -c -k --keepParent "$app_path" "$submission_zip"
xcrun notarytool submit "$submission_zip" --key "$api_key_path" --key-id "$api_key_id" --issuer "$api_issuer" --wait --output-format json
xcrun stapler staple "$app_path"
codesign --verify --deep --strict --verbose=2 "$app_path"
spctl --assess --type execute --verbose=2 "$app_path"
```
Validate JSON status Accepted explicitly, not just command stdout existence. Then create signed DMG, notarize that DMG as well, staple it and run stapler validate. Do not log credentials/decoded key contents; restrict temporary secret-file permissions, clean only known temp keychain/key paths, preserve user's existing keychain state.
- [ ] Public workflow uploads DMG/checksum/release notes only after tests, signing, notarization and stapler verification pass. Use exact tagged commit SHA in evidence. A failed public release stays failed; it never falls back to an unsigned public upload.
- [ ] Run fake release tests and available unsigned verification, record signed validation as pending until actual credentials are provided. Commit:
```bash
git add scripts .github docs
git commit -m "ci: gate notarized releases with protected signing credentials"
```

### Task 3: Cask, documentation and release evidence

**Files:** scripts/render-cask.sh, scripts/tests/release-contract-tests.sh, Casks/macdevclean.rb when actual inputs exist, README.md, README.pt-BR.md, CHANGELOG.md, MacDevCleanApp/Resources/Assets.xcassets/AppIcon.appiconset, docs/release/{checklist,homebrew-tap}.md, docs/demo/, docs/verification/09-distribution.md.

**Interfaces:** render-cask.sh --owner <owner> --repo <repo> --version <semver> --sha256 <digest> --output <path> generates Casks/macdevclean.rb. The shell option parser passes five literal arguments to a Ruby generator; never interpolate user values into Ruby source. Use this generator body:
```ruby
owner, repo, release_version, checksum, output = ARGV
abort "Expected five arguments" unless ARGV.length == 5
abort "Invalid owner" unless owner.match?(/\A[A-Za-z0-9][A-Za-z0-9-]*\z/)
abort "Invalid repository" unless repo.match?(/\A[A-Za-z0-9][A-Za-z0-9_.-]*\z/)
abort "Invalid version" unless release_version.match?(/\A\d+\.\d+\.\d+\z/)
abort "Invalid checksum" unless checksum.match?(/\A[0-9a-f]{64}\z/)
abort "Output exists" if File.exist?(output)
text = <<~CASK
  cask "macdevclean" do
    version "#{release_version}"
    sha256 "#{checksum}"
    url "https://github.com/#{owner}/#{repo}/releases/download/v#{release_version}/MacDevClean-#{release_version}.dmg"
    name "MacDevClean"
    desc "Inspect and clean developer storage on macOS"
    homepage "https://github.com/#{owner}/#{repo}"
    depends_on macos: ">= :sonoma"
    app "MacDevClean.app"
  end
CASK
File.write(output, text)
```
Do not generate the production cask until release inputs are known. No uninstall zap of caches/projects/Trash/history; standard cask uninstall only removes the app.

- [ ] Add generator test with synthetic owner test-owner, repository test-repo, version 1.0.0 and digest 64 a characters; assert exact interpolation, Ruby syntax and invalid argument rejection. Assert output contains only the app installation stanza and no zap, uninstall script, Trash or cache path. Never upload this test cask. Run red, implement formatter, run green.
- [ ] Document independent repository homebrew-macdevclean with Casks/macdevclean.rb; command `brew install --cask OWNER/macdevclean/macdevclean`. Tap creation/push waits for authorization; local definition/testing proceeds. Homebrew audit/install needs a real accessible release; mark pending until then, never substitute a fabricated URL. Re-check current Cask requirements before submission.
- [ ] Add README English and pt-BR with value, screenshot/demo from fixture mode, supported rules, warnings, truthful Trash semantics, minimum OS, Xcode setup, architecture diagram, exact test commands, unsigned vs signed distribution and known limitations. Describe real engineering choices, not invented benchmarks or endorsements. ADRs must include consequences, rejected alternatives and links to actual tests.
- [ ] Include icon assets with a simple original storage/cleaning motif (no Apple or tool logos copied from mockup); verify Dock icon at 16–1024 px. Add copyright attribution for original work and dependency notices. Do not choose an open-source license for the user silently: record license decision as a pre-publication owner action unless previously specified; local development continues.
- [ ] Add release checklist: clean checkout build, all suites, localization, VoiceOver manual pass, minimum-supported OS test evidence, both CPU architectures compiled with available hardware smoke coverage recorded, signed/notarized DMG evidence, quarantined-download launch on test Mac, cask install/uninstall on disposable test account, no user data removed, checksum/release notes, security docs and owner authorization. Missing minimum-OS/hardware testing is explicit, not “supported and verified.”
- [ ] Run full verify.sh and release tests; branch review; commit and merge into develop:
```bash
git add README.md README.pt-BR.md CHANGELOG.md docs scripts .github MacDevCleanApp
git commit -m "docs: document installation safety architecture and release evidence"
```
Add Casks/macdevclean.rb only if generated with real artifact data. Create release/1.0.0 for final gates.
- [ ] Once release checklist is complete and remote publication authorized, use:
```bash
git switch main
git merge --no-ff release/1.0.0 -m "release: MacDevClean 1.0.0"
git tag -a v1.0.0 -m "MacDevClean 1.0.0"
git switch develop
git merge --no-ff main -m "merge: synchronize release 1.0.0"
```
Push and publish only within that explicit authorization. If blocked by credentials or infrastructure, keep release candidate branch and deliver local artifact plus exact remaining checklist.

## Exit gate

Local app/DMG and scripts verified. Public release is complete only with real signing, notarization, install and remote evidence. Report development completion separately from publication completion. No fabricated v1.0.0 release.
