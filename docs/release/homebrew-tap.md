# Homebrew tap

**No tap exists, and `Casks/macdevclean.rb` is deliberately absent.** A cask
whose `url` and `sha256` do not describe a published artifact fails at install
time, for everyone, after they trusted it. The generator is written and tested;
it runs when there is a real release to describe.

## The repository

A tap is its own repository, named `homebrew-<tap>`, owned by the same person
who owns the release:

```text
homebrew-macdevclean/
└── Casks/
    └── macdevclean.rb
```

Users then install with:

```bash
brew install --cask OWNER/macdevclean/macdevclean
```

Creating that repository and pushing to it **requires the owner's
authorization**, which has not been given. Nothing in this repository pushes
anywhere.

## Generating the cask

After a release exists and its DMG has been downloaded from the release page:

```bash
shasum -a 256 MacDevClean-1.0.0.dmg
bash scripts/render-cask.sh \
    --owner OWNER --repo REPO --version 1.0.0 \
    --sha256 THE_DIGEST_FROM_THE_LINE_ABOVE \
    --output Casks/macdevclean.rb
```

Take the checksum from **the downloaded artifact**, not from the build machine.
They should match; checking is how you find out that they do.

`scripts/render-cask.sh` passes five literal arguments to
`scripts/render-cask.rb`, which validates each one — owner, repository, a
`major.minor.patch` version, 64 lowercase hex characters — and refuses to
overwrite an existing file. Nothing is spliced into Ruby source.

## What the cask does and does not do

```ruby
app "MacDevClean.app"
```

That is the whole installation. There is **no `zap` stanza**, no `uninstall`
script, no `preflight` and no `postflight`, and the contract tests assert their
absence.

The reason is specific to this product. MacDevClean's own history is the record
of files it moved to the Trash. A `zap` that cleared
`~/Library/Application Support/MacDevClean/` on uninstall would destroy exactly
the evidence a user needs if something went wrong — and a `zap` that reached
into caches or Trash would be the tool deleting things during its own removal.
Uninstalling removes the application. Removing the rest is the user's decision,
documented in [manual-install.md](manual-install.md).

## Before submitting anywhere

- `brew audit --cask --new` and `brew install --cask` against the **real**
  published URL. Neither has run: there is no published URL.
- Re-read the current Homebrew cask requirements. They change, and the rules
  that applied when this was written may not be the rules that apply then.
- Verify the DMG is notarized and stapled. Homebrew installs it on other
  people's machines; Gatekeeper is what protects them, not the tap.
- Install and uninstall on a **disposable test account**, and confirm that
  after uninstalling, a developer's caches, projects, Trash and MacDevClean
  history are all still there.

None of these has been performed. They are listed in
[docs/testing/manual-release-checks.md](../testing/manual-release-checks.md).
