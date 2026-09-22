# Defect report — first owner run of the 1.0.0 build

Reported by the repository owner on 2026-09-21, after running the unsigned
local build (`dist/MacDevClean-1.0.0-unsigned.dmg`). This is the **first time
the application has been exercised by a person**: the XCUITest gate has never
run on the development machine, so every defect below is in territory no
automated check covered.

Each entry states the symptom as reported, what the code actually does, whether
the cause is confirmed or still a hypothesis, and what "fixed" means. The plan
that implements these is
[2026-09-21-10-defect-remediation.md](../plans/2026-09-21-10-defect-remediation.md).

## D1 — Counts render as raw markup

**Reported.** On Overview, the Cache categories card shows
`^[0 category](inflect: true) · Zero kB` in its top-right corner. After a scan,
the line under "Scan again" shows
`^[193 item](inflect: true) encontrado em ^[8 categoria](inflect: true)`.

**Confirmed.** Two independent causes produce the same symptom.

*D1a — `Text` built by string concatenation.* Four call sites concatenate
`String` values and hand the result to `Text`, which selects the
`Text(_ content: String)` overload. That overload is **verbatim**: no catalog
lookup, no inflection, no translation.

| Location | What it produces |
|---|---|
| `MacDevCleanApp/Features/Overview/OverviewView.swift:172` | The Cache categories header the owner reported |
| `MacDevCleanApp/Features/CleanupReview/ReviewView.swift:108` | The same pattern in the review header |
| `MacDevCleanApp/Features/Caches/CachesView.swift:241` | An entire sentence that is **always English**, in both languages |
| `MacDevCleanApp/Features/Caches/CategoryRow.swift:53` | An accessibility label assembled from translated fragments |

*D1b — the catalog has no plural variations.*
`MacDevCleanApp/Resources/Localizable.xcstrings` holds **232 keys, of which 13
carry `^[…](inflect: true)` markup and 0 have plural variations**. The catalog
was generated as flat `stringUnit` entries, so the markup sits inside the
*value* and reaches the screen intact.

The owner's second screenshot proves the lookup itself works: the surrounding
words came back in Portuguese ("encontrado em") while the markup stayed
literal. The string was found and translated; only the inflection was never
resolved.

**Fixed means.** No string that reaches a screen contains `^[` or
`](inflect:`. Counts are localized through **plural variations** in the
catalog, with matching categories in both languages. No user-visible `Text` is
assembled with `+`. A test resolves every catalog key at counts 0, 1 and 2 and
fails if any resolved string still contains the markup — so this cannot come
back silently.

## D2 — Large Files says it is not built, and it is

**Reported.** Choosing "Arquivos grandes" shows text saying the feature does
not exist yet, and the sidebar disappears, leaving the owner stuck.

**Confirmed, and the feature exists.** `MacDevCleanApp/App/ContentView.swift`
routes `.largeFiles` to `UpcomingFeatureView`. That route was written in plan
05, when the screen really was a placeholder. Plan 06 then built the whole
feature — `LargeFilesView`, `LargeFileRowView`, `LargeFilesModel`, the
`LargeFileScanner`, 7 model tests and 3 UI tests — and **nobody updated the
route**. The coordinator already builds `largeFiles` in its initializer.

This is the single most valuable fix in this document, and the smallest.

**Fixed means.** `.largeFiles` renders `LargeFilesView`. A test asserts that
**no destination in the sidebar routes to a placeholder**; if a future
destination ever does, its sidebar entry is hidden instead of offered.

## D3 — The sidebar disappears and the window becomes a dead end

**Reported.** On Large Files and on Exclusions, the sidebar vanishes and there
is no way back to the other screens.

**Cause not confirmed.** `ExclusionsView` is fully implemented, so this is not
D2 repeating. The sidebar is a `NavigationSplitView` column whose visibility is
never pinned: `ContentView` constructs `NavigationSplitView { sidebar } detail:
{ detail }` with no `columnVisibility` binding and no split-view style. macOS
may then collapse the column, and nothing in the app can bring it back — there
is no toolbar control, and the window minimum (1100 pt) is enforced on the
split view as a whole rather than reserving room for both columns.

Detail screens also differ in what they declare: `CachesView`, `HistoryView`
and `LargeFilesView` set `navigationTitle` and some set toolbars, while others
do not, which changes how the split view sizes them.

**Fixed means.** The sidebar is always present and always reachable at the
1100×720 minimum, from every destination, in both languages. The implementer
must **reproduce the defect first** and record which of these it was, because a
fix that cannot be demonstrated to remove the symptom is not a fix.

## D4 — Caches is misaligned and "Start scan" does nothing

**Reported.** The Caches screen is visually broken, and the start-scan button
does not respond at all.

**Two confirmed causes, one to confirm.**

*Layout.* `CachesView.toolbar` is one `HStack` holding three `Picker`s
(capped at 260, 180 and 170 points), a "Select all low and medium risk" button
and a `Spacer`, with nothing that wraps. Below the window's own minimum width,
the row overflows.

*The dead button.* The empty state offers "Start scan", which calls
`RootCoordinator.startScan()`:

```swift
var canScan: Bool { !roots.isEmpty && !scanModel.isScanning }

func startScan() {
    guard canScan else { return }
    …
}
```

When `canScan` is false the call **returns silently**. The button stays
enabled, nothing happens, and nothing explains why. A control that cannot act
must not look like one that can.

*Also likely.* The list is built from `model.visibleCandidates`, but the empty
state is chosen from `model.candidates`. When a filter excludes everything —
which happens the moment a category is tapped on Overview, because that sets
`ecosystemFilter` — both `ordinary` and `highRisk` are empty and the screen
renders an empty scroll area with no message.

**Fixed means.** The toolbar wraps instead of overflowing at 1100 pt. "Start
scan" is disabled when it cannot act, states the reason, and offers the action
that resolves it. Caches shows scan progress and a Cancel control while a scan
is running, instead of looking inert. A filter that matches nothing says so and
offers to clear itself.

## D5 — History with nothing in it

**Reported.** Suspected broken; needs checking.

**Not reproduced.** `HistoryView` renders an `EmptyStateView` when
`model.sessions.isEmpty`, and its toolbar has "Open Trash" plus "Clear
history…", the second already disabled when empty. Nothing in the code obviously
breaks, so this is most likely D3 seen from another screen.

**Fixed means.** With no history: the sidebar is present, the empty state is
readable in both languages, "Clear history…" is disabled, and "Open Trash"
either works or is not offered. Confirmed by running it, not by reading it.

## D6 — Nothing is on GitHub

**Confirmed.** `origin` is `git@github.com:danielcbdev/mac-dev-clean.git` and
`origin/main` points at `7ec895d`, the pre-development commit. **No work from
plans 01–09 has been pushed.** `develop` and `release/1.0.0` do not exist on the
remote.

This was never a defect: pushing needs the owner's authorization, which had not
been given, so the work stayed local by design and every document says so.

**Fixed means.** With the owner's explicit authorization, `main`, `develop` and
`release/1.0.0` are pushed. **No tag is pushed**, because `v1.0.0` does not
exist and must not until the release checklist passes.

Pushing also produces something this project has never had: **a CI run on a
real runner**. `ci.yml` calls `scripts/verify.sh` without
`MACDEVCLEAN_SKIP_UI_TESTS`, so GitHub's macOS runner will attempt the 21 UI
tests that have never run here. Whatever it reports — pass or fail — is the
first real evidence about them, and it is recorded as measured.

## D7 — Screens that are not implemented

**Reported.** Implement the small ones; hide the buttons for the rest.

**Assessment.** After D2 there is nothing left to hide: Overview, Caches, Large
Files, History, Exclusions and Settings are all implemented. The rule the owner
asked for still becomes policy, enforced by a test — a destination that has no
screen is not offered in the sidebar.

## What must not change

These are not up for renegotiation while fixing the above.

- Filesystem cleanup stays `FileManager.trashItem` only.
- Moving to the Trash is never described as freeing space.
- A scan still selects nothing, and high-risk items stay unselectable from the
  list.
- No fix may be verified by cleaning the owner's real data. Destructive tests
  keep using owned fixtures with fake Trash and fake Docker adapters.
- A check that did not run is recorded as not run, never as a pass.
