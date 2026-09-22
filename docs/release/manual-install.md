# Installing the local development build

**This artifact is unsigned and not notarized.** It is a development build, not
a release. macOS will treat it as such, and the steps below do not ask you to
turn that protection off.

## Build it yourself

```bash
bash scripts/build-local.sh --version 1.0.0 --output dist/local
bash scripts/verify-artifact.sh --app dist/local/MacDevClean.app --mode unsigned
bash scripts/package-dmg.sh --app dist/local/MacDevClean.app \
    --output dist/MacDevClean-1.0.0-unsigned.dmg
```

`build-local.sh` refuses a version that is not `major.minor.patch`, refuses to
overwrite an app already in the output directory, and passes the version to
`xcodebuild` as a build setting rather than as shell text. `package-dmg.sh`
refuses an output path that already exists. Neither touches `/Applications`.

## What was actually produced here

On 2026-09-21, with Xcode 27.0 (27A266a) on macOS 27.0 (26A428):

| Fact | Value |
|---|---|
| App | `dist/local/MacDevClean.app`, 8.3 MB |
| Binary | `Mach-O universal (x86_64 arm64)` |
| Signature | `adhoc, linker-signed` — **not** a Developer ID signature |
| Minimum system version | 14.0 |
| Disk image | `dist/MacDevClean-1.0.0-unsigned.dmg`, 3,082,529 bytes |
| SHA-256 | `120ccb600f345c8c398402fcabc9eed6b728b06984af506ba0d34bf3001fa79f` |

`verify-artifact.sh --mode unsigned` passed on that app. The `x86_64` slice is a
compilation fact: **the application has never been run on Intel hardware**, and
only macOS 27.0 was available, so the macOS 14.0 claim is a deployment target,
not an observation.

`hdiutil create` prints a deprecation warning on macOS 27 recommending
`diskutil image create`. It still works, and it is what runs on the supported
toolchain, so it is unchanged.

## Opening it

1. Open the disk image and drag `MacDevClean.app` to `/Applications`, or run it
   straight from `dist/local/`.
2. The first launch of an unsigned app is refused with "cannot be opened because
   it is from an unidentified developer". **Control-click the app and choose
   Open**, then confirm. That approves this one application.
3. If it was downloaded rather than built locally, macOS also applies a
   quarantine flag, and System Settings → Privacy & Security will offer "Open
   Anyway" after the first refusal.

Do not disable Gatekeeper, and do not run `spctl --master-disable`. Turning off
a protection for the whole machine to run one development build is a bad trade,
and nothing here requires it.

## What the app does on first launch

It starts idle. It scans nothing until you choose project folders and press the
scan action.

It creates `~/Library/Application Support/MacDevClean/store.sqlite` for its
settings and its record of what it did. Cleanup is offered only when that store
opens: a cleanup whose record disappears on quit is not offered at all. See
[ADR 0006](../adr/0006-local-persistence.md).

## Removing it

Delete the application, and delete
`~/Library/Application Support/MacDevClean/` if you also want its settings and
history gone. Nothing else is written outside that folder — no launch agent, no
login item, no privileged helper.

## Not verified here

The application **was not launched** during this build session, deliberately:
the Release composition would create the Application Support store on the
machine doing the verification. Launch, first-run behaviour, quarantined
download and Intel hardware remain in
[docs/testing/manual-release-checks.md](../testing/manual-release-checks.md).
