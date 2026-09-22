# Release configuration

**No value in this document is real, and none is stored in this repository.**
Everything below is configured by the owner, in GitHub, before a public release
is possible. `scripts/release-preflight.sh --mode public` fails and names the
variables that are missing; it never prints a value, a length or a prefix.

None of this is configured today. See
[docs/verification/09-distribution.md](../verification/09-distribution.md).

## What a public release needs

| Name | Where it lives | What it is |
|---|---|---|
| `MACDEVCLEAN_RELEASE_OWNER` | repository or environment **variable** | the GitHub owner the release belongs to |
| `MACDEVCLEAN_RELEASE_REPO` | repository or environment **variable** | the repository name |
| `MACDEVCLEAN_BUNDLE_ID` | repository or environment **variable** | the owner's reverse-DNS bundle identifier |
| `APPLE_TEAM_ID` | environment **secret** | the Apple Developer team identifier |
| `APPLE_CERTIFICATE_P12_BASE64` | environment **secret** | the Developer ID Application certificate and private key, base64 |
| `APPLE_CERTIFICATE_PASSWORD` | environment **secret** | the password that `.p12` was exported with |
| `APPLE_API_KEY_ID` | environment **secret** | App Store Connect API key identifier |
| `APPLE_API_ISSUER_ID` | environment **secret** | App Store Connect issuer UUID |
| `APPLE_API_PRIVATE_KEY` | environment **secret** | the contents of the `.p8` notarization key |

The first three are configuration rather than secrets, and they have no
defaults on purpose: a guessed owner publishes to the wrong place.

The bundle identifier is `br.com.dcbeng.macdevclean`, a reverse-DNS
identifier on a domain the owner controls. `MACDEVCLEAN_BUNDLE_ID` must match
it, or notarization belongs to somebody else's namespace.

## Where they are attached

All of them belong to a **protected GitHub environment named `release`**, with
required reviewers. Repository-wide secrets would be reachable by any workflow
in the repository; an environment secret is reachable only by a job that names
that environment and waits for its approval.

`.github/workflows/release.yml` is built around that:

- It has no pull-request trigger of any kind. Code from a fork cannot reach a
  job that holds credentials, because no fork event starts this workflow.
- `permissions: contents: read` at the top. The only job that raises it is
  `publish`, which runs last and only after signing, notarization and stapling
  have all passed.
- The signing job and the publishing job both name the `release` environment.
- Artifacts move between jobs through this run's own artifact store, fetched
  with the preinstalled `gh` CLI rather than a third-party action.

## Getting the values

These steps happen in the owner's Apple and GitHub accounts. **Nothing here can
be done on the owner's behalf, and no credential was created, bought or
requested during development.**

1. A paid Apple Developer membership.
2. In Certificates, Identifiers & Profiles, create a **Developer ID
   Application** certificate. Export it from Keychain Access as `.p12` with a
   password, then `base64 -i certificate.p12 | pbcopy`.
3. In App Store Connect → Users and Access → Integrations, create an API key
   with the **Developer** role. The `.p8` downloads exactly once.
4. In the repository, Settings → Environments → `release`: add the secrets, add
   the variables, and add yourself as a required reviewer.

Delete the exported `.p12` and `.p8` from disk afterwards. `.gitignore` already
refuses to commit `*.p12`, `*.p8` and `*.keychain-db`, and
`scripts/verify-artifact.sh` refuses any app bundle that carries one.

## What the signing script does with them

`scripts/sign-notarize.sh` writes the certificate and the key into a
`mktemp -d` directory at mode 600, imports the certificate into a **temporary
keychain it creates**, and on every exit — including failure — restores the
keychain search list it found and deletes that keychain. It prints no secret.

It does not use `codesign --deep`: nested components are signed first,
individually, and the application last, so nothing inherits options it was
never reviewed for.

Notarization is checked by **parsing the JSON status and requiring exactly
`Accepted`**. A command that exits zero having printed something else is not a
pass.

One accepted weakness: `security import` takes the certificate password as a
command-line argument, which is visible to `ps` while it runs. There is no file
or stdin form of that flag. On an ephemeral, single-tenant runner this is
acceptable; **do not run this script on a shared machine.**

## Before the first real release

- **Re-verify every pinned action SHA against GitHub.** `release.yml` reuses
  the `actions/checkout` and `actions/upload-artifact` revisions already pinned
  in `ci.yml`. They were pinned in an earlier milestone and have not been
  re-checked against the upstream repositories since.
- Confirm the `release` environment really requires a reviewer. An environment
  without one gives the same reach as a repository secret.
- Work through [checklist.md](checklist.md).
