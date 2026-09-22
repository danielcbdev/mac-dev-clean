# 10 — Defect remediation

Evidence for [plan 10](../superpowers/plans/2026-09-21-10-defect-remediation.md)
against the six defects in the
[defect report](../superpowers/specs/2026-09-21-defect-report.md).

Nothing here is a summary of what should have happened. Every command, exit
status and observation below was produced on this machine on the date given, or
is recorded as not run.

## Toolchain and gate

```
$ MACDEVCLEAN_SKIP_UI_TESTS=1 bash scripts/verify.sh
```

| | |
|---|---|
| Date | 2026-09-22 |
| Exit status | **0** |
| Xcode | 27.0 (build 27A266a) |
| Swift | 6.4 (swiftlang-6.4.0.34.1, clang-2100.3.34.1) |
| Target | arm64-apple-macosx27.0.0 |
| Tests executed | **295**, 0 failures, 0 unexpected |
| Release build | unsigned, succeeded |
| Checkers | token access, localization, release contracts, policy, lint, whitespace — all passed |

295 is the previous 278 plus the 17 tests added here: 7 in
`CatalogRenderingTests`, 5 in `NavigationTests`, 5 in `ScanAvailabilityTests`.
The catalog went from 232 keys to 248: 13 retired, 2 deleted with the
placeholder, and 31 added for the plural variations and the sentences that
used to be assembled with `+`.

The gate was run again after every fix in this document had landed, with the
same result.

### NOT RUN: the XCUITest suite

`MACDEVCLEAN_SKIP_UI_TESTS=1` was set. The 21 UI tests — now 24 with
`NavigationUITests` — **did not run**. This is a missing gate, not a pass. It
is the same blocker recorded since plan 05, and it is why these defects reached
the owner.

The blocker was measured more precisely this time, and it is narrower than
previously recorded. See "What the accessibility interface can and cannot do".

## Method

The XCUITest gate does not run here, so the interface was driven directly
instead: the Debug fixture build was launched with `open`, and its window was
observed and operated through the macOS accessibility interface. That is not a
substitute for XCUITest — it proves nothing about whether the UI suite passes —
but it is first-hand observation of the running application rather than
inference from source, and every claim below marked *observed* was seen on
screen.

### What the accessibility interface can and cannot do

Previously recorded as "the app launched by XCUITest exposes no window to the
accessibility interface", and treated as a property of the app. Measured on
2026-09-22, it is narrower:

| Launch | Window at the window server | Window exposed to accessibility |
|---|---|---|
| Debug fixture build via `open` | yes, titled and sized | **yes** — fully inspectable and clickable |
| Release build via `open` | none observed | n/a |
| XCUITest | not retested | still blocked |

So the app is inspectable when launched normally. Whatever prevents XCUITest
from seeing it is specific to the XCUITest launch, not to the application. This
narrows the blocker; it does not remove it, and the UI suite still has not run.

## The build used for manual verification, and a correction to the plan

Plan 10 Task 4 and the task brief both prescribe:

```bash
bash scripts/build-local.sh --version 1.0.1 --output dist/local
open dist/local/MacDevClean.app --args --ui-testing --scenario mixed-results
```

**That does not produce a fixture run.** `build-local.sh` builds Release, and
the fixture composition is `#if DEBUG`:

- `PreviewDependencies.swift` is wrapped in `#if DEBUG` in its entirety
  (lines 1 and 188), so `PreviewScenario`, `PreviewTrash`, `PreviewDocker` and
  `PreviewFixtureWorld` do not exist in Release.
- `AppDependencies.live` consults `PreviewScenario.parse` only inside
  `#if DEBUG` (lines 61–65), and `fixture(scenario:)` is itself inside
  `#if DEBUG` (lines 124–185).
- `SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)"` appears exactly
  once in `project.pbxproj`, at line 320, inside the configuration block that
  ends `name = Debug;` at line 324. The Release block, ending at line 348,
  defines nothing.

In Release the arguments are therefore accepted and ignored, and the app runs
its real composition against the owner's configured folders and against
`~/Library/Application Support/MacDevClean/store.sqlite`.

The safety property is correct and deliberate — a shipping binary must not be
talkable into fixture mode. The instruction was wrong. `scripts/run-fixture.sh`
now builds Debug and is what
[docs/testing/manual-defect-script.md](../testing/manual-defect-script.md)
tells the owner to use.

### Side effect to disclose

Before this was understood, the Release build was launched once with the
fixture arguments, at 09:20 on 2026-09-22. It opened the owner's existing
`store.sqlite`. Checked immediately afterwards:

- `store.sqlite` — modification time unchanged at `Sep 21 19:12:42`, the
  owner's own first run.
- `store.sqlite-wal` — unchanged at `Sep 21 23:22:49`.
- `store.sqlite-shm` — touched at `Sep 22 09:20:33`. That file is ephemeral
  shared memory, recreated on every open.

No cleanup was run, no history was written or removed, and no file was moved.
The app was quit. Nothing else on the machine was touched.

Separately, `defaults delete dev.macdevclean.app` was run while investigating
D3, which removed persisted window position and split-view sizes for the app.
It touches no history, no settings and no file. The prior contents were
exported first to `/tmp/macdevclean-defaults-backup.plist`.

## D1 — Counts render as raw markup

**Fixed. Verified by test and observed on screen.**

The catalog held 232 keys, 13 carrying `^[…](inflect: true)` inside the value
and **zero** plural variations. All 13 are now plural variations; two further
keys carrying a bare `%lld` were pluralized for the same reason.

The defect report listed four `Text` values built by string concatenation.
There were **nine**. The other five were found by grepping for the pattern
after the first four were fixed:

| Location | What it produced |
|---|---|
| `DockerDetailsView` | "About " never translated |
| `CleanupResultsView` | " moved to the Trash" never translated |
| `ReviewView` | the "• " bullet, and the issue text verbatim |
| `OverviewView` | "about " on the Docker card, never translated |
| `StorageSummaryView` | the whole VoiceOver summary, built with plain Swift interpolation and never localized in either language |

All nine are gone. `grep` for a user-visible `Text` assembled with `+` across
`Features`, `App` and `DesignSystem` returns nothing.

*Red before the fix.* `CatalogRenderingTests`: **7 tests, 181 failures**.

*Green after.* 7 tests, 0 failures, inside the 295 above.

*Observed on screen*, Debug fixture build, pt-BR, 1102 × 774, after a real
fixture scan of 7 items in 5 categories — the two strings the owner reported,
with live counts:

- Overview status line: **"O MacDevClean encontrou 7 itens em 5 categorias."**
- Cache categories header: **"5 categorias · 10,4 MB"**

and the plural boundaries, by selecting items in Caches:

| Selected | Footer | Button |
|---|---|---|
| 0 | `0 itens selecionados` | `Revisar 0 selecionados` |
| 1 | `1 item selecionado` | `Revisar 1 selecionado` |
| 7 | `7 itens selecionados` | `Revisar 7 selecionados` |

The footer sentence that used to be English in both languages now reads
"Cerca de 10,4 MB vai para a Lixeira. Isso só libera espaço quando você a
esvazia." No markup anywhere.
[images/d1-overview-after.png](images/d1-overview-after.png),
[images/d1-d4-caches-after-plural.png](images/d1-d4-caches-after-plural.png).

### A measured correction to the plan

Plan 10 states that in Brazilian Portuguese "a count of zero takes `other`".
It does not. CLDR places 0 in pt-BR's `one` category, so a plain one/other pair
renders `0 categoria`. This was found by the test failing on exactly that
assertion.

Foundation honours an explicit `zero` variation ahead of the CLDR rule — probed
by adding one and re-running the test, which then passed. The four keys a user
sees at zero (`%lld category`, `%lld item selected`, `%lld file selected`,
`Review %lld selected`) declare `zero` in both languages. The rest do not,
because they are only rendered at one or more.

### Regression barriers added

`check-localization.swift` rejects: a value containing the markup; a key with
`%lld`/`%ld`/`%d` and no plural variations; plural categories that differ
between `en` and `pt-BR`; an empty variation value. These rules run **before**
the guards that skip a key, so a key missing a translation is still checked for
markup. Four new fixtures, one per rule, are asserted rejected — each for its
own stated reason, verified in the checker's output.

`check-policy.sh` rejects the markup in production Swift, excluding the XCTest
groups, because `CatalogRenderingTests` must be able to name what it forbids.
Fixture `policy-inflection` is asserted rejected.

## D2 — Large Files says it is not built

**Fixed.**

`.largeFiles` routed to `UpcomingFeatureView`. Routing is now data:
`Destination.screenKind`, `Destination.isAvailable` and
`Destination.sidebarItems`.

*Red before the fix.* `NavigationTests`: 5 tests, **3 failures**, including
`("placeholder") is not equal to ("largeFiles")`.

*Green after.* 5 tests, 0 failures.

*Observed on screen*: choosing "Arquivos grandes" opens the real screen, with
"Escolher pastas…", the smallest-size picker and the sort picker, where it
previously showed "Arquivos grandes ainda não foi construído". A screenshot of
the defect is at [images/d2-d3-largefiles-before.png](images/d2-d3-largefiles-before.png).

Re-confirmed after the D3 fix, on the restored routing: toolbar at y = 64,
empty state centred, footer at y = 735, sidebar present.

## D3 — The sidebar empties and the window becomes a dead end

**Reproduced, cause isolated, FIXED. Verified on screen.**

### What was observed, before the fix

Debug fixture build, pt-BR, window at 1102 × 774.

| Screen | Sidebar | Detail |
|---|---|---|
| Visão geral | all six rows, header and footer | correct |
| Caches | rows drawn overlapping at the very top | toolbar at y = **−128**, footer at y = **973**, in a 774-tall window |
| Arquivos grandes | **entirely blank**, column at full width | toolbar at y = **−1258**, footer at y = **2107** |
| Histórico | **entirely blank**, column at full width | empty state correct and centred |

Screenshots: [images/d4-caches-before.png](images/d4-caches-before.png),
[images/d2-d3-largefiles-before.png](images/d2-d3-largefiles-before.png),
[images/d5-history-before.png](images/d5-history-before.png).

### The cause

`.fixedSize(horizontal: false, vertical: true)` on a long `Text`, in a view
used as the root of a `NavigationSplitView` detail column.

`fixedSize(vertical: true)` proposes `nil` width to the text, which then
reports its **ideal** size — for a sentence of that length, its full unwrapped
single-line width, several hundred points. The `frame(maxWidth: 420)` wrapped
around it does not clamp that, because a maximum only binds a proposal that
exists. The view's ideal width ballooned, the split view sized itself from it,
and the sidebar column kept its width while drawing no rows at all.

`EmptyStateView` carries that modifier and is the root of the empty state on
History, Large Files and Caches. Overview escaped because its root is a
`ScrollView`, which proposes a definite width.

### What the defect report got wrong

It proposed that macOS collapses the sidebar because no `columnVisibility`
binding pins it. **The column is never collapsed.** It keeps its full width —
measurably, in the accessibility tree — and draws no rows. An empty column and
a collapsed column are different failures, and only the second is what
`columnVisibility` addresses.

It also suggested the detail screens differ in declaring `navigationTitle`.
They do not: all six declare one.

### How it was isolated

Fifteen builds, each launched and observed. The screen was locked for part of
this, which is why the harness routes every destination to one screen: the
first render alone answers the question, and screenshots work while locked.

| Changed | Sidebar |
|---|---|
| Detail replaced with a plain `Text` | survives |
| Detail replaced with a short-message `EmptyStateView` | survives |
| Detail replaced with the real `HistoryView` | blank, from the first render |
| `HistoryView` without `.toolbar` | blank |
| `HistoryView` without `.confirmationDialog` | blank |
| `HistoryView` without `.task` | blank |
| `HistoryView` without `DisclosureGroup` | blank |
| root `Group { if/else }` wrapped in `ZStack` | blank |
| `sessionCard` reduced to `Card { Text }` | blank |
| `sessionCard` reduced to `Text` | blank |
| the `sessionCard(session)` call inlined | blank |
| **empty-state message shortened to one short line** | **survives** |
| long message restored, `.fixedSize` removed from `EmptyStateView` | **survives** |

The twelfth row is the discriminator, and the thirteenth names the mechanism:
the message length mattered, and the modifier that made length matter is
`fixedSize`.

### The fix

`.fixedSize(horizontal: false, vertical: true)` removed from three places where
the parent does not guarantee a definite width:

- `EmptyStateView`, the shared root of the empty states.
- The `LargeFilesView` footer note.
- The `CachesView` high-risk introduction.

The remaining 27 uses are inside rows and cards nested in a `ScrollView`, which
proposes a definite width, and are left alone. Each removal carries a comment
naming the mechanism, so it is not re-added as a tidy-up.

Text still wraps: the surrounding `frame(maxWidth: 420)` bounds it, and a
`VStack` in a vertically free container lets it grow.

### Verified on screen, after the fix

Same build, same window size, same language. Sidebar present with all six rows
on **every** destination, and every control inside the window:

| Screen | Toolbar y | Footer y | Sidebar |
|---|---|---|---|
| Arquivos grandes | **64** (was −1258) | **735** (was 2107) | all six rows |
| Caches | **64** and **96**, two rows | **734** (was 973) | all six rows |
| Histórico | n/a | n/a | all six rows |

[images/d4-caches-after.png](images/d4-caches-after.png),
[images/d5-history-after.png](images/d5-history-after.png).

### One further finding

AppKit persists the split view's subview frames per app:

```
"NSSplitView Subview Frames …SidebarNavigationSplitView" = (
    "0.000000, 0.000000, 220.000000, 1590.500000, NO, NO",
    "220.000000, 0.000000, 882.000000, 1590.500000, NO, NO"
);
```

A height of 1590.5 in a 774-tall window, written to `defaults` and restored on
the next launch. The broken geometry therefore survived quitting the app, which
is why the state looked sticky to the owner. `defaults delete
dev.macdevclean.app` clears it; it touches no history, settings or file.

## D4 — Caches is misaligned and "Start scan" does nothing

**Fixed at the model level and in the layout. The layout is not yet verified on
screen.**

*Layout.* The toolbar was a single non-wrapping `HStack`. Measured at the
window minimum in Portuguese it did not merely clip: it pushed the whole screen
past the window's height, placing the controls 128 points above the top edge
and the footer 200 below the bottom. It is a `ViewThatFits` now, falling back to
two rows.

*The dead button.* `startScan()` opened with `guard canScan else { return }`
while the control stayed enabled. `RootCoordinator.scanUnavailableReason` is
now a value; the control is disabled whenever it is non-`nil`, the reason is
stated beneath it, and `.noRoots` offers the action that resolves it.

*Filtered to nothing.* Caches listed `visibleCandidates` but chose its empty
state from `candidates`. `ScanModel.hasResultsHiddenByFilters` separates the two
answers, and the screen offers to clear the filters.

*Scan progress.* Caches shows the visited count and a control to stop, instead
of looking inert.

*Red before the fix.* `ScanAvailabilityTests`: **5 tests, 5 failures**,
including `a refused scan must not look started` — the scan really did start
with no roots configured.

*Green after.* 5 tests, 0 failures.

*Verified on screen*, 1102 × 774, pt-BR: the toolbar wraps to two rows, the
three pickers at y = 64 and the two buttons at y = 96, everything between
x = 248 and x = 883 and inside the window. The footer sits at y = 734. Before
the fix the same controls were at y = −128 and the footer at y = 973.
[images/d4-caches-after.png](images/d4-caches-after.png).

**Not run:** the `.noRoots` refusal on screen. Reaching Caches with no roots
configured requires getting past onboarding without adding a folder, which was
not attempted. The behaviour is covered by `ScanAvailabilityTests`, and step
4b of the manual script asks the owner to try it.

## D5 — History with nothing in it

**Reproduced, and it is not History. Fixed with D3.**

*Observed*: the History screen is correct — "Nenhuma limpeza ainda" with a
readable explanation in pt-BR, "Apagar histórico…" disabled, "Abrir Lixeira"
present. What is broken is the sidebar, blank as in D3.

The defect report's suspicion that D5 is D3 seen from another screen is
confirmed by observation rather than by reading. **D5 closed when D3 did**:
verified on screen after the fix, with the sidebar present and the empty state
correct. [images/d5-history-after.png](images/d5-history-after.png).

## D6 — Nothing is on GitHub

**Already done, before this plan.** `git ls-remote --heads origin` lists
`main`, `develop` and `release/1.0.0`. `git ls-remote --tags origin` is empty.
`v1.0.0` does not exist and must not until
[docs/release/checklist.md](../release/checklist.md) passes.

The CI run that plan 10 Task 5 expects — `ci.yml` calling `verify.sh` **without**
the skip, attempting the UI tests on a real runner for the first time — has not
been triggered for this branch. Recorded as not run.

## D7 — Screens that are not implemented

**Closed by policy rather than by hiding anything.** Every destination is
built, so nothing is hidden. `NavigationTests` enforces the rule the owner
asked for: a destination with no screen is not offered in the sidebar.

## Summary

| Defect | State | Test that fails without the fix | Observed on screen |
|---|---|---|---|
| D1 counts as markup | fixed | CatalogRenderingTests, 181 failures | yes, at 0, 1 and 7 |
| D2 Large Files placeholder | fixed | NavigationTests, 3 failures | yes |
| D3 sidebar empties | fixed | none — a layout defect no model test can reach | yes, on every destination |
| D4 Caches layout and dead button | fixed | ScanAvailabilityTests, 5 failures | layout yes; the refusal not run |
| D5 History | fixed with D3 | — | yes |
| D6 GitHub | done before this plan | — | — |

## Still unproven

- **The XCUITest suite, now 24 tests, has never run.** It is the gate that
  would have caught D2, D3 and D5, and it is still the gap that let them reach
  the owner. Driving the interface through the accessibility interface is not
  the same gate: it proves the screens behave, not that the suite passes.
- **No CI run exists.** `GET /repos/danielcbdev/mac-dev-clean/actions/runs`
  returns `total_count: 0`, and `actions/workflows` returns `total_count: 0`,
  both HTTP 200 with a token carrying `repo` scope. The push of `develop` on
  2026-09-22 produced no run, and neither did the push before it. `main`, the
  default branch, carries `.github/` but no `workflows/` directory, which is
  consistent with GitHub listing no workflows for the repository. Recorded as
  measured; the cause is not confirmed and no workaround was applied.
- **D3 has no automated regression test.** It is a layout defect in a
  `NavigationSplitView` column; no model-level test can observe it. The guard
  is `NavigationUITests.testTheSidebarSurvivesVisitingEveryDestination`, which
  has never run, plus step 3 of the manual script and the comments left at each
  removal site.
- The manual script has not been run by the owner.
- The `.noRoots` refusal has not been seen on screen.
- Nothing here was run on macOS 14, on Intel, or against a signed build.
