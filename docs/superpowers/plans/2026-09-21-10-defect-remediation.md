# Defect Remediation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix every defect found in the owner's first real run, make each fix provable by a test that would have caught it, and publish the work to the existing remote with authorization.

**Architecture:** No new modules. The defects are in the interface layer, the String Catalog and the routing table; the core packages are untouched except where a test needs a new observable.

**Tech Stack:** SwiftUI, Observation, String Catalogs, XCTest/XCUITest, GitHub Actions.

**Spec:** [Defect report](../specs/2026-09-21-defect-report.md); [approved specification](../specs/2026-09-21-macdevclean-design.md); [contracts](../specs/2026-09-21-interface-contracts.md).

## Global Constraints

- Product: MacDevClean; desktop application. Swift 6 language mode; deployment target macOS 14; the exact tested Xcode build is recorded.
- UI: English and Brazilian Portuguese; source, commits and technical documentation in English.
- SwiftUI, Observation, structured Swift Concurrency, Foundation, SwiftData and XCTest. No production runtime dependency outside Apple frameworks.
- Filesystem cleanup is Trash-only. No permanent deletion, no empty-Trash command, no `rm`, `rmdir` or `removeItem` in production code.
- Tests operate on owned synthetic fixtures and fake destructive adapters; never on the owner's caches, real Trash or existing Docker resources.
- Branch from `develop` as `fix/interface-defects`; Conventional Commits; `--no-ff` merges. `main` is not touched except by the authorized push in Task 5.
- A check that did not run is recorded as not run, never as a pass. `docs/verification/10-defects.md` records real commands, real exit statuses and real dates.
- **The XCUITest gate has never run on the development machine.** Where a fix can only be shown at the interface, it is verified by the owner following the manual script in Task 4, and by CI in Task 5. Neither is replaced by an assertion that it "should" work.

## Review Focus

- A count that renders its own markup is worse than an untranslated count: Task 1.
- A destination that cannot be left traps the user: Tasks 2 and 3.
- A control that cannot act must not look like one that can: Task 3.
- A push is irreversible in the sense that matters — it is public: Task 5.

---

## Scope and files

Prerequisites: plans 01–09, merged into `develop`. Branch: `fix/interface-defects`.

Create:
- `MacDevCleanApp/MacDevCleanAppTests/{CatalogRenderingTests,NavigationTests,ScanAvailabilityTests}.swift`.
- `MacDevCleanUITests/NavigationUITests.swift`.
- `docs/testing/manual-defect-script.md`.
- `docs/verification/10-defects.md`.

Modify: `MacDevCleanApp/Resources/Localizable.xcstrings`, `ContentView.swift`, `OverviewView.swift`, `CachesView.swift`, `CategoryRow.swift`, `ReviewView.swift`, `RootCoordinator.swift`, `scripts/check-localization.swift`, `scripts/check-policy.sh`, `docs/progress.md`, `CHANGELOG.md`.

Delete, if Task 2 leaves it unused: `MacDevCleanApp/DesignSystem/UpcomingFeatureView.swift`.

---

### Task 1: Counts that render as words, in both languages

**Files:** `MacDevCleanApp/Resources/Localizable.xcstrings`, `OverviewView.swift`, `CachesView.swift`, `CategoryRow.swift`, `ReviewView.swift`, `LargeFilesView.swift`, `HistoryView.swift`, `StorageSummaryView.swift`, `DockerDetailsView.swift`, `CleanupResultsView.swift`, `IrreversibleConfirmationView.swift`, `scripts/check-localization.swift`, `scripts/check-policy.sh`, `MacDevCleanAppTests/CatalogRenderingTests.swift`.

**Interfaces:** every user-visible count is one catalog key with **plural variations**, formatted with `%lld`. No `^[` anywhere in source or catalog. No user-visible `Text` assembled with `+`.

- [ ] Write the regression test first, and run it **red**. It must fail today on at least the Overview status line and the Cache categories header:
```swift
func testNoResolvedStringLeaksInflectionMarkup() throws {
    let keys = try CatalogRenderingTests.loadCatalogKeys()
    for key in keys {
        for count in [0, 1, 2] {
            for language in ["en", "pt-BR"] {
                let rendered = CatalogRenderingTests.render(key, count: count, language: language)
                XCTAssertFalse(
                    rendered.contains("^["),
                    "\(language) \(key) at \(count) still shows markup: \(rendered)")
                XCTAssertFalse(rendered.contains("](inflect:"), rendered)
            }
        }
    }
}
```
Add named tests for the two strings the owner reported, asserting the exact expected text in both languages — for example `1 categoria`, `8 categorias`, and the English equivalents.
- [ ] Convert all **13** keys carrying `^[…](inflect: true)` to plural variations. Both languages must declare the **same categories**; Brazilian Portuguese uses `one` and `other`, and a count of zero takes `other`:
```json
"%lld item selected" : {
  "localizations" : {
    "en" : { "variations" : { "plural" : {
      "one" : { "stringUnit" : { "state" : "translated", "value" : "%lld item selected" } },
      "other" : { "stringUnit" : { "state" : "translated", "value" : "%lld items selected" } }
    } } },
    "pt-BR" : { "variations" : { "plural" : {
      "one" : { "stringUnit" : { "state" : "translated", "value" : "%lld item selecionado" } },
      "other" : { "stringUnit" : { "state" : "translated", "value" : "%lld itens selecionados" } }
    } } }
  }
}
```
A sentence containing **two** counts — "Found N items across M categories" — cannot be expressed as one plural variation. Split it into two keys and compose them in a third key that takes both already-formatted strings as `%@`, or restructure the sentence. **Do not** concatenate translated fragments.
- [ ] Remove the four `Text(… + …)` call sites listed in the defect report. Each becomes a single key with placeholders:
```swift
// Before — verbatim, untranslated, markup intact:
Text("^[\(count) category](inflect: true) · " + ByteLabel.format(bytes))
// After — one key, one lookup:
Text("\(categoriesLabel) · \(ByteLabel.format(bytes))")
```
`CategoryRow`'s accessibility label becomes one key with three placeholders, so its word order is translatable.
- [ ] Extend `scripts/check-localization.swift` to fail when: any catalog value contains `^[` or `](inflect:`; a key whose name contains a `%lld` placeholder has no plural variations; the plural categories declared for `en` and `pt-BR` differ; or a variation value is empty. Add a fixture under `scripts/tests/fixtures/` for each new rule and assert rejection in `scripts/tests/check-localization-tests.sh`.
- [ ] Add a rule to `scripts/check-policy.sh` rejecting `^[` in production Swift, with a fixture that must be rejected.
- [ ] Run the tests and the checkers green. Commit:
```bash
git add MacDevCleanApp scripts docs
git commit -m "fix: render counts as words instead of catalog markup"
```

### Task 2: Every destination reaches its screen, and none is a dead end

**Files:** `MacDevCleanApp/App/ContentView.swift`, `MacDevCleanApp/App/AppState.swift`, `MacDevCleanAppTests/NavigationTests.swift`, `MacDevCleanUITests/NavigationUITests.swift`, possibly deleting `UpcomingFeatureView.swift`.

**Interfaces:** `Destination` gains `var isAvailable: Bool`. The sidebar lists only available destinations. The detail area has no placeholder branch for an available destination.

- [ ] Write the test first, and run it **red** — it fails today because `.largeFiles` is routed to a placeholder:
```swift
func testEveryDestinationOfferedInTheSidebarHasAScreen() {
    for destination in Destination.sidebarItems {
        XCTAssertNotEqual(
            destination.screenKind, .placeholder,
            "\(destination) is offered in the sidebar but shows a placeholder")
    }
}

func testAnUnavailableDestinationIsNotOfferedAtAll() {
    for destination in Destination.allCases where destination.screenKind == .placeholder {
        XCTAssertFalse(Destination.sidebarItems.contains(destination))
    }
}
```
Make the routing table **data rather than control flow** — a `screenKind` on `Destination` that the view switches on — because a `switch` buried in a view is what let a built feature keep advertising itself as missing.
- [ ] Route `.largeFiles` to `LargeFilesView`, matching how `.history`, `.exclusions` and `.settings` are already wired. Check the initializer against `LargeFilesView`'s actual signature; the coordinator already builds the model in its initializer.
- [ ] If no destination is left unavailable, delete `UpcomingFeatureView.swift` and its catalog keys. Dead scaffolding that claims a feature does not exist is worse than absent.
- [ ] Pin the sidebar so a destination can always be left. Bind `NavigationSplitView(columnVisibility:)` to a `@State` of `.all`, give the split view an explicit style, and make sure the detail column's minimum width still leaves the sidebar its 200 pt at the 1100 pt window minimum:
```swift
@State private var columns: NavigationSplitViewVisibility = .all
NavigationSplitView(columnVisibility: $columns) { sidebar } detail: { detail }
    .navigationSplitViewStyle(.balanced)
```
Give every detail screen a `navigationTitle`, so none of them changes how the split view sizes itself.
- [ ] Add `MacDevCleanUITests/NavigationUITests.swift`: visit all six destinations in order, asserting after each that `sidebar.overview` still exists and that the destination's own identifier appears. It will not run locally — write it anyway; Task 5 runs it on CI.
- [ ] Run the model tests green. Commit:
```bash
git add MacDevCleanApp MacDevCleanUITests
git commit -m "fix: route Large Files to the screen that was already built"
```

### Task 3: Caches that fits, explains itself, and never looks inert

**Files:** `MacDevCleanApp/Features/Caches/CachesView.swift`, `MacDevCleanApp/App/RootCoordinator.swift`, `MacDevCleanApp/Features/Overview/ScanModel.swift` if a reason code is needed, `MacDevCleanAppTests/ScanAvailabilityTests.swift`.

**Interfaces:** `RootCoordinator` exposes `var scanUnavailableReason: ScanUnavailableReason?` — `nil` when a scan can start, `.noRoots` or `.alreadyScanning` otherwise. No control that calls `startScan()` is enabled while that value is non-nil.

- [ ] Write the tests first, and run them **red**:
```swift
func testAScanCannotStartWithoutRootsAndSaysWhy() async {
    let coordinator = RootCoordinator(dependencies: .fixture(scenario: .firstRun))
    await coordinator.load()

    XCTAssertEqual(coordinator.scanUnavailableReason, .noRoots)
    coordinator.startScan()
    XCTAssertFalse(coordinator.scanModel.isScanning, "a refused scan must not look started")
    XCTAssertNil(coordinator.scanModel.snapshot)
}

func testAFilterThatMatchesNothingIsDistinctFromHavingNothing() async throws {
    // A scan with results, then a filter that excludes all of them.
    // The screen must say the filter is the reason, and offer to clear it.
    XCTAssertTrue(model.hasResultsHiddenByFilters)
}
```
- [ ] Make the toolbar survive the minimum window. Wrap the three pickers and the bulk-selection button in `ViewThatFits`, falling back to two rows, or move the filters into a `Menu`. No fixed English-width assumptions: Brazilian Portuguese labels are longer.
- [ ] Disable "Start scan" whenever `scanUnavailableReason != nil`, state the reason beneath it, and offer the action that resolves it — for `.noRoots`, a control that opens where project roots are added. A disabled control with an explanation is honest; an enabled control that does nothing is not.
- [ ] Show the scan on this screen while it runs: the visited count the model already publishes, and a Cancel control wired to `coordinator.cancelScan()`. A user who presses Start must see that something started.
- [ ] Add the filtered-to-nothing state: when `candidates` is non-empty and `visibleCandidates` is empty, say that the filters hide everything and offer to clear them.
- [ ] Run tests green. Commit:
```bash
git add MacDevCleanApp
git commit -m "fix: make the Caches screen fit, explain itself and show scan progress"
```

### Task 4: Reproduce, then prove, by hand

**Files:** `docs/testing/manual-defect-script.md`, `docs/testing/accessibility.md`.

The XCUITest gate does not run on the development machine, so the owner is the instrument. This task produces the script they follow and records what they saw.

- [ ] Write `docs/testing/manual-defect-script.md`: a numbered script that takes under ten minutes, covering every reported defect, in both languages, at the 1100×720 minimum window. For each step: what to do, what must happen, and a place to record what actually happened. It must include the **pre-fix reproduction** of D3 and D5, because those causes are unconfirmed and a fix for a symptom nobody reproduced is a guess.
- [ ] Build the fixture composition for the run, so nothing touches real data:
```bash
bash scripts/build-local.sh --version 1.0.1 --output dist/local
open dist/local/MacDevClean.app --args --ui-testing --scenario mixed-results
```
State plainly in the script that a plain launch of the Release build writes `~/Library/Application Support/MacDevClean/store.sqlite`, and that the fixture launch does not.
- [ ] Record the results as observations, with the date, the build and the language. An unchecked line stays unchecked. Commit:
```bash
git add docs
git commit -m "docs: record the manual verification of the reported defects"
```

### Task 5: Publish, and find out what CI says

**Files:** `docs/verification/10-defects.md`, `docs/progress.md`, `CHANGELOG.md`, possibly `.github/workflows/ci.yml`.

**This task requires the owner's explicit authorization, in this session, before any command runs.** The remote is `git@github.com:danielcbdev/mac-dev-clean.git`. Pushing is public and irreversible in the way that matters.

- [ ] Merge `fix/interface-defects` into `develop` with `--no-ff` after reviewing the full branch diff, and re-run the gate:
```bash
MACDEVCLEAN_SKIP_UI_TESTS=1 bash scripts/verify.sh
```
- [ ] Ask for authorization. On an explicit yes, push **branches only, no tags**:
```bash
git push origin main develop 'refs/heads/release/1.0.0'
git log --oneline -1 origin/develop
```
`v1.0.0` does not exist and must not be created: most of `docs/release/checklist.md` is unchecked.
- [ ] Watch the CI run. `ci.yml` calls `scripts/verify.sh` **without** `MACDEVCLEAN_SKIP_UI_TESTS`, so the runner attempts the 21 UI tests that have never run. Record what actually happened:
  - If they pass, say so, with the run URL — that is the first evidence the interface works at runtime, and `docs/verification/05-interface.md` should be updated to say the blocker was local.
  - If they fail, record the failure verbatim and treat it as the next defect. **Do not** add `MACDEVCLEAN_SKIP_UI_TESTS=1` to CI to make the badge green; a skipped gate is recorded as skipped, in the workflow and in the evidence.
- [ ] Write `docs/verification/10-defects.md` with the gate output, the manual script results, the CI run and its URL, and what remains unproven. Update `docs/progress.md` and `CHANGELOG.md`. Commit and merge:
```bash
git add docs CHANGELOG.md
git commit -m "docs: record defect remediation evidence and the first CI run"
```

## Exit gate

All six reported defects fixed, each with a test that fails without the fix. No
string reaching a screen contains catalog markup. Every sidebar destination
opens its screen and can be left. "Start scan" either scans or explains why it
cannot. The manual script has been run by the owner and its results recorded as
observations. The work is on GitHub and the first CI run is recorded as it
happened, whatever it said. `v1.0.0` still does not exist.
