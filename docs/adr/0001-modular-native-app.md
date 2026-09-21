# ADR 0001: A native app over one multi-target local package

- **Status:** Accepted
- **Date:** 2026-09-21
- **Plan:** 01 foundation, Task 3

## Context

MacDevClean moves a developer's build artifacts and caches to the Trash and
removes Docker resources. A defect costs the user data. The specification
therefore requires cleanup authority to live below the user interface, a
testable architecture, and a build a stranger can clone and run without a paid
Apple account.

Three shapes were available: one monolithic Xcode target; six separate Swift
packages; or one native Xcode app over a single local package split into six
targets.

## Decision

Use a native Xcode application target that depends on one local Swift package,
`MacDevCleanCore`, split into six production targets — `Domain`,
`CleanupRules`, `Scanning`, `Cleanup`, `DockerIntegration`, `Persistence` — plus
a `TestSupport` target used only by tests.

Dependency direction always points inward toward `Domain`, which imports only
Foundation. The application layer owns UI composition, macOS lifecycle,
resources and dependency construction.

There is no server, no privileged helper, no background agent, and no
third-party runtime dependency. Every production import is an Apple framework.

## Consequences

**What this buys.** The compiler enforces the safety boundary: `Cleanup` owns
the validated-plan types with internal initializers, so no other target —
including the app — can construct one and skip policy. `Domain`'s Foundation-only
import is checked by the build, not by review. Each target's tests run in
seconds under `swift test`, without launching an app.

**What it costs.** Six targets in one package rather than six packages means
they version together and cannot be consumed independently. That is the right
trade here: there is no external consumer, and six packages would add manifest
and resolution overhead for a benefit nobody needs. Splitting later is
mechanical if it ever becomes useful.

**Rejected alternatives.** One monolithic target would have left the safety
boundary as a convention that review must police, and would have forced every
unit test through an app host. Six separate packages would have added
cross-package version churn with no consumer to justify it.

**No privileged helper.** The app runs as the user, without administrator
authentication. It therefore cannot clean anything the user could not delete in
Finder — which is the intended limit, not a shortcoming.

**No runtime dependency.** Any future build-tooling dependency needs its own
ADR. Runtime dependencies stay prohibited.
