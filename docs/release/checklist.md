# Release checklist

Every line is a gate. A line that has not been done is not a line to skip, and
"it should work" is not a check. Where this repository can prove something, the
proof is linked; where it cannot, the line says so.

**Status: development is complete; publication is not started.** Items 1–4 pass
today. Items 5 onward have never run, because they need credentials, a second
machine, or hardware that was not available.

## 1. Clean checkout

- [x] The working tree is clean and the branch is merged through `develop`.
- [ ] Build from a **fresh clone** rather than an incremental tree. Not done:
      the artifact in this repository was built from the working tree.

## 2. Every suite

- [x] `bash scripts/verify.sh` exits 0.
      On 2026-09-21: 278 tests run, 0 failures. See
      [docs/verification/09-distribution.md](../verification/09-distribution.md).
- [ ] **UI tests pass.** 21 are written and compile; they have never run. The
      XCUITest gate is unavailable on this machine. See
      [docs/verification/05-interface.md](../verification/05-interface.md).

## 3. Localization

- [x] `swift scripts/check-localization.swift` passes: 232 keys, English and
      Brazilian Portuguese, no stale states, matching plural placeholders.
- [ ] Read the interface in both languages at the minimum window size. Not
      done; no screenshots exist.

## 4. The artifact

- [x] `bash scripts/build-local.sh --version X.Y.Z --output dist/local`.
- [x] `bash scripts/verify-artifact.sh --app … --mode unsigned` passes:
      universal `arm64` + `x86_64`, minimum system version 14.0, icon present,
      no signing material and no fixture resources inside the bundle.
- [x] `bash scripts/package-dmg.sh` produces the image, and its SHA-256 is
      recorded: `120ccb600f345c8c398402fcabc9eed6b728b06984af506ba0d34bf3001fa79f`
      for the unsigned 1.0.0 build of 2026-09-21.
- [ ] **Launch the built application.** Not done deliberately: the Release
      composition would write a store into Application Support on the verifying
      machine.

## 5. Accessibility, by hand

- [ ] VoiceOver reads the summary ring, every risk label, the review warning
      and the irreversible confirmation.
- [ ] Keyboard-only navigation of all six screens; Escape dismisses the review
      and never starts a cleanup.
- [ ] Reduce Motion, Increase Contrast, Reduce Transparency, large text.

None performed. [docs/testing/accessibility.md](../testing/accessibility.md).

## 6. Platform coverage

- [ ] **Launches on macOS 14**, the declared minimum. Only macOS 27.0 was
      available. The deployment target is a claim, not an observation.
- [ ] **Runs on Intel hardware.** Only Apple Silicon was available. The
      `x86_64` slice is a compilation fact.

## 7. Signing and notarization

- [ ] `bash scripts/release-preflight.sh --mode public` passes. It currently
      fails, correctly, naming nine missing variables.
- [ ] A Developer ID Application certificate and an App Store Connect API key
      exist, in a protected `release` environment with a required reviewer.
      [configuration.md](configuration.md).
- [ ] `notarytool` returns `Accepted` for both the app and the disk image.
- [ ] `stapler validate` passes on both.
- [ ] `spctl --assess --type execute` passes.
- [ ] `verify-artifact.sh --mode signed` passes on the signed app.

## 8. Download and install as a stranger would

- [ ] Download the published DMG **on a different Mac**, so it carries the
      quarantine flag, and open it without any Gatekeeper override.
- [ ] Confirm the app launches, the window appears, and nothing is scanned
      until asked.

## 9. Homebrew

- [ ] Generate the cask from the **published** URL and the checksum of the
      **downloaded** artifact. [homebrew-tap.md](homebrew-tap.md).
- [ ] `brew audit --cask --new` passes.
- [ ] Install and uninstall on a disposable test account, and confirm the
      uninstall leaves caches, projects, Trash and MacDevClean history intact.

## 10. Safety, stated plainly in the release notes

- [ ] The notes say that moving to the Trash does not free space until the
      Trash is emptied in Finder.
- [ ] The notes say Docker operations are not recoverable.
- [ ] The notes do not claim any performance improvement. Clearing a cache
      makes the next build slower.
- [ ] The notes state which platforms were actually tested, separately from
      which platforms are supported.

## 11. Authorization

- [x] The owner has chosen a licence: MIT, recorded in `LICENSE`.
- [x] The owner has authorized publishing an unsigned GitHub Release.
- [ ] The owner has **not** authorized signing with their credentials or
      creating a Homebrew tap. Those remain unauthorized until asked for
      separately.
- [x] The bundle identifier belongs to a domain the owner controls:
      `br.com.dcbeng.macdevclean`.

## 12. Only then

```bash
git switch main
git merge --no-ff release/1.0.0 -m "release: MacDevClean 1.0.0"
git tag -a v1.0.0 -m "MacDevClean 1.0.0"
```

**`v1.0.0` must not be created while anything above is unchecked.** A tag is a
statement that the version passed its gates. It has not been created.
