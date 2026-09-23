# Redesign Overview Screen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restyle the app shell's sidebar and the Overview screen (all four of its states: with results, never scanned, scanning, and the shared chrome) to match the approved redesign spec, using the `Theme`/`Typography`/`Layout`/`RiskBadge`/button-style foundation already merged.

**Architecture:** Presentation-only changes inside `MacDevCleanApp/App/ContentView.swift` (sidebar) and `MacDevCleanApp/Features/Overview/` (two new state views plus edits to the existing three files). No change to `ScanModel`, `RootCoordinator`, or any package below the app target — this plan only re-skins views that already exist and adds two new ones for states the spec treats as full-screen takeovers rather than in-card messages.

**Tech Stack:** Swift 6, SwiftUI.

**Spec:** [docs/references/redesign/design-tokens.md](../../references/redesign/design-tokens.md) for tokens; screens `1a` (Overview, results, light), `1b` (results, dark), `1i` (never scanned, light), `1j` (scanning, dark) in [docs/references/redesign/MacDevClean Redesign.dc.html](../../references/redesign/MacDevClean%20Redesign.dc.html).

## Global Constraints

- Swift 6, macOS 14 minimum deployment. Native SwiftUI only.
- Use `Theme`/`Typography`/`Layout`/`RiskBadge`/`PrimaryButtonStyle`/`SecondaryButtonStyle` from `docs/superpowers/plans/2026-09-22-00-redesign-foundation.md` — do not reintroduce hardcoded hex colors or system semantic colors (`.green`, `.blue`, `.secondary`, etc.) in the files this plan touches.
- **Do not draw fake window chrome.** The spec's screens show three colored dots and a sidebar-toggle icon because the design tool is simulating "this is a macOS window" for a static mockup. The real app window already draws real traffic-light buttons and a real sidebar toggle via AppKit/`NavigationSplitView` — this plan must not add SwiftUI views that imitate them.
- **Do not invent scan progress data the domain doesn't produce.** The spec's scanning-state mockup (`1j`) shows "62 / 193", a percentage bar, a live file path, and a partial GB total. `ScanModel` only exposes `visited` (a running count with no denominator) while a scan is active — no total, no current path, no partial byte total (`knownFilesystemBytes` reads from `snapshot`, which is `nil` until the scan finishes). Adding those would mean fabricating numbers, which conflicts with this project's truthful-reporting principle (`AGENTS.md`). The redesigned scanning card shows only what `ScanModel` actually has: the running `visited` count, an indeterminate progress indicator, and the cancel action.
- **Do not reintroduce the D3 sidebar-emptying defect.** `EmptyStateView.swift` documents that a long `Text` carrying `.fixedSize(horizontal: false, vertical: true)` at the root of the detail column previously caused the sidebar to render with no rows (see `docs/verification/10-defects.md`). The new "never scanned" full-screen state must follow the same safe pattern `EmptyStateView` already uses: bound long text with `.frame(maxWidth:)`, never `.fixedSize(vertical: true)`, on a `VStack` in a vertically free container.
- This codebase does not unit-test SwiftUI view bodies (confirmed: no test file references `OverviewView`, `StorageSummaryView`, or `CategoryRow`; `ScanModelTests`/`NavigationTests` test behavior instead). Tasks in this plan that are pure view restyling verify by a successful build (`xcodebuild build`) rather than a new unit test — consistent with this project's existing convention. A task that introduces new decision *logic* still gets a real test.
- Branch: `feature/new-design` (current branch, owner-authorized), same as the foundation plan.
- Commits: small, Conventional Commits, one per task.

---

## Task 1: Restyle the sidebar chrome

**Files:**
- Modify: `MacDevCleanApp/App/ContentView.swift`

**Interfaces:**
- Consumes: `Theme.sidebarBackground/.accentSoft/.accentText/.textPrimary/.textTertiary/.separator` (existing `Theme` from the foundation plan), `Typography.title/.caption` + `View.appFont`.
- Produces: no new public interface — `ContentView`'s sidebar keeps its existing `List(Destination.sidebarItems, ...)` structure and accessibility identifiers; only colors/fonts/spacing change.

- [ ] **Step 1: Restyle the sidebar's background, wordmark and footer**

In `MacDevCleanApp/App/ContentView.swift`, change the `sidebar` computed property's `safeAreaInset(edge: .top, ...)` block:

```swift
.safeAreaInset(edge: .top, spacing: 0) {
    VStack(alignment: .leading, spacing: 4) {
        Text("MacDevClean")
            .appFont(Typography.title)
            .fontWeight(.bold)
            .foregroundStyle(Theme.textPrimary)
        Text("Understand it before you remove it.")
            .appFont(Typography.caption)
            .foregroundStyle(Theme.textTertiary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, Layout.space12)
    .padding(.top, Layout.space12)
    .padding(.bottom, Layout.space8)
}
```

And the `safeAreaInset(edge: .bottom, ...)` block:

```swift
.safeAreaInset(edge: .bottom, spacing: 0) {
    Label("Nothing is removed until you confirm.", systemImage: "hand.raised")
        .appFont(Typography.caption)
        .foregroundStyle(Theme.textTertiary)
        .padding(Layout.space12)
        .frame(maxWidth: .infinity, alignment: .leading)
}
```

Note: the message `Text` in the top inset keeps no `.fixedSize` (it never had one), and this edit does not add one — see the Global Constraints note on the D3 defect.

Add `.scrollContentBackground(.hidden)` and `.background(Theme.sidebarBackground)` to the `List` itself, so the sidebar surface uses the spec's `--side` token instead of the system sidebar material:

```swift
private var sidebar: some View {
    List(Destination.sidebarItems, id: \.self, selection: $coordinator.destination) {
        destination in
        Label(destination.title, systemImage: destination.symbol)
            .accessibilityIdentifier(destination.accessibilityID)
    }
    .listStyle(.sidebar)
    .scrollContentBackground(.hidden)
    .background(Theme.sidebarBackground)
    .safeAreaInset(edge: .top, spacing: 0) {
        // (block above)
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
        // (block above)
    }
    .navigationSplitViewColumnWidth(
        min: Layout.sidebarMinimum,
        ideal: Layout.sidebarIdeal,
        max: Layout.sidebarMaximum
    )
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodebuild -workspace MacDevClean.xcworkspace -scheme MacDevClean -destination 'platform=macOS' -derivedDataPath .build/xcode build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add MacDevCleanApp/App/ContentView.swift
git commit -m "feat(overview): restyle sidebar chrome with redesign tokens"
```

---

## Task 2: Redesign the Overview header

**Files:**
- Modify: `MacDevCleanApp/Features/Overview/OverviewView.swift`

**Interfaces:**
- Consumes: `Theme.textPrimary/.textSecondary`, `Typography.hero` + `View.appFont`.
- Produces: `OverviewView.header` keeps its name and position in `body`; the `trustIndicator` computed property is removed (not present in the spec's screen `1a`/`1b` header — the same trust message already exists in the info-cards row below).

- [ ] **Step 1: Replace the header**

Replace the `header` and `trustIndicator` properties in `OverviewView.swift`:

```swift
private var header: some View {
    VStack(alignment: .leading, spacing: 6) {
        Text("Clean with confidence")
            .appFont(Typography.hero)
            .foregroundStyle(Theme.textPrimary)
            .accessibilityIdentifier("app.title")
        Text(
            """
            Find developer caches and build artifacts, understand what removing each \
            one costs you, then decide.
            """
        )
        .font(.title3)
        .foregroundStyle(Theme.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }
}
```

Remove the `trustIndicator` property entirely, and remove its call site from `body` (the `HStack` wrapping `header` and `trustIndicator` collapses to just `header`, called directly where `header` was referenced).

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodebuild -workspace MacDevClean.xcworkspace -scheme MacDevClean -destination 'platform=macOS' -derivedDataPath .build/xcode build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add MacDevCleanApp/Features/Overview/OverviewView.swift
git commit -m "feat(overview): redesign header, drop the trust card the spec doesn't show"
```

---

## Task 3: Redesign the ring/summary card

**Files:**
- Modify: `MacDevCleanApp/Features/Overview/StorageSummaryView.swift`
- Modify: `MacDevCleanApp/Features/Overview/OverviewView.swift`

**Interfaces:**
- Consumes: `Theme.neutral` (ring track), `Typography.metric` + `View.appFont` (ring center number), `PrimaryButtonStyle` (Task 6 of the foundation plan).
- Produces: `StorageSummaryView.color(for:)` keeps its existing signature and category→color mapping (the spec gives no concrete per-category hex — only a generic 4-shade legend — so the existing, already-distinguishable mapping stays); only the ring's center text style and the "Review cleanup" button's style change.

- [ ] **Step 1: Restyle the ring's center number**

In `StorageSummaryView.swift`, change the center `VStack`:

```swift
VStack(spacing: 2) {
    Text(ByteLabel.format(knownBytes))
        .appFont(Typography.metric)
        .foregroundStyle(Theme.textPrimary)
        .minimumScaleFactor(0.5)
        .lineLimit(1)
    Text("Potential cleanup")
        .appFont(Typography.caption)
        .foregroundStyle(Theme.textSecondary)
}
.padding(Layout.ringStroke * 2)
```

Change the track circle's color from `.quaternary`/`.secondary` to `Theme.neutral`:

```swift
if reduceTransparency {
    Circle().stroke(Theme.textTertiary, lineWidth: Layout.ringStroke)
} else {
    Circle().stroke(Theme.neutral, lineWidth: Layout.ringStroke)
}
```

- [ ] **Step 2: Apply the primary button style to "Review cleanup"**

In `OverviewView.swift`'s `summaryColumn`, change:

```swift
Button {
    coordinator.openReview()
} label: {
    Label("Review cleanup", systemImage: "arrow.right")
        .labelStyle(.titleAndIcon)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
}
.buttonStyle(.borderedProminent)
.controlSize(.large)
.disabled(model.snapshot == nil)
.accessibilityIdentifier("cleanup.reviewFromOverview")
```

to:

```swift
Button {
    coordinator.openReview()
} label: {
    Label("Review cleanup", systemImage: "arrow.right")
        .labelStyle(.titleAndIcon)
        .frame(maxWidth: .infinity)
}
.buttonStyle(.macDevPrimary)
.disabled(model.snapshot == nil)
.accessibilityIdentifier("cleanup.reviewFromOverview")
```

- [ ] **Step 3: Build to verify it compiles**

Run: `xcodebuild -workspace MacDevClean.xcworkspace -scheme MacDevClean -destination 'platform=macOS' -derivedDataPath .build/xcode build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add MacDevCleanApp/Features/Overview/StorageSummaryView.swift MacDevCleanApp/Features/Overview/OverviewView.swift
git commit -m "feat(overview): restyle the potential-cleanup ring and its primary button"
```

---

## Task 4: Redesign the categories card and row

**Files:**
- Modify: `MacDevCleanApp/Features/Caches/CategoryRow.swift`
- Modify: `MacDevCleanApp/Features/Overview/OverviewView.swift`

**Interfaces:**
- Consumes: `Theme.textPrimary/.textSecondary/.textTertiary/.separator`, `Typography.title/.body/.caption` + `View.appFont`, `Layout.controlRadius`.
- Produces: `CategoryRow`'s public API (`CategoryRow(summary:action:)`) is unchanged — used at 2 existing call sites (`OverviewView.categoriesColumn`, `CachesView`) with no signature change.

- [ ] **Step 1: Restyle `CategoryRow`'s icon tile per the spec (26pt, 7pt radius)**

In `CategoryRow.swift`, change the icon tile:

```swift
Image(systemName: CategoryNaming.symbol(summary.category))
    .font(.system(size: 13, weight: .semibold))
    .foregroundStyle(.white)
    .frame(width: 26, height: 26)
    .background(
        StorageSummaryView.color(for: summary.category),
        in: .rect(cornerRadius: 7)
    )
    .accessibilityHidden(true)
```

Change the title/detail/size text to use the new type tokens:

```swift
VStack(alignment: .leading, spacing: 2) {
    Text(CategoryNaming.title(summary.category))
        .appFont(Typography.body)
        .fontWeight(.medium)
        .foregroundStyle(Theme.textPrimary)
        .fixedSize(horizontal: false, vertical: true)
    Text(CategoryNaming.detail(summary.category))
        .appFont(Typography.caption)
        .foregroundStyle(Theme.textTertiary)
        .fixedSize(horizontal: false, vertical: true)
}

Spacer(minLength: 12)

VStack(alignment: .trailing, spacing: 2) {
    ByteLabel(bytes: summary.knownBytes, style: .body.weight(.medium))
        .foregroundStyle(Theme.textPrimary)
    RiskBadge(risk: summary.highestRisk)
}

Image(systemName: "chevron.right")
    .font(.caption.weight(.semibold))
    .foregroundStyle(Theme.textTertiary)
    .accessibilityHidden(true)
```

- [ ] **Step 2: Restyle the categories card header in `OverviewView.categoriesColumn`**

```swift
HStack {
    Text("Cache categories")
        .appFont(Typography.title)
        .foregroundStyle(Theme.textPrimary)
    Spacer()
    Text(
        LocalizedFormatters.text(
            "%1$@ · %2$@", locale: locale,
            LocalizedFormatters.count(
                "%lld category", model.filesystemSummaries.count,
                locale: locale),
            LocalizedFormatters.bytes(
                model.knownFilesystemBytes, locale: locale))
    )
    .appFont(Typography.caption)
    .foregroundStyle(Theme.textTertiary)
    .monospacedDigit()
}
.padding(.bottom, 8)
```

Change the row `Divider()` to use `Theme.separator`:

```swift
Divider()
    .overlay(Theme.separator)
    .opacity(summary.id == model.filesystemSummaries.first?.id ? 0 : 1)
```

- [ ] **Step 3: Build to verify it compiles**

Run: `xcodebuild -workspace MacDevClean.xcworkspace -scheme MacDevClean -destination 'platform=macOS' -derivedDataPath .build/xcode build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add MacDevCleanApp/Features/Caches/CategoryRow.swift MacDevCleanApp/Features/Overview/OverviewView.swift
git commit -m "feat(overview): restyle the categories card and row per the redesign spec"
```

---

## Task 5: Redesign the Docker card and info cards

**Files:**
- Modify: `MacDevCleanApp/Features/Overview/OverviewView.swift`
- Modify: `MacDevCleanApp/DesignSystem/InfoCard.swift`

**Interfaces:**
- Consumes: `Theme.accentSoft/.accentText/.textPrimary/.textSecondary`, `Typography.title/.body/.caption` + `View.appFont`, `SecondaryButtonStyle`.
- Produces: `InfoCard`'s public API (`InfoCard(symbol:tint:title:message:)`) is unchanged — its 3 existing call sites in `OverviewView.cards` keep passing `.green`/`.blue`/`.purple` as `tint`; the spec doesn't specify distinct per-card tints beyond the shared `--acSoft`/`--acTxt` pair used for its icon badges elsewhere, so the existing three system-color tints are kept (they already satisfy "never colour alone" — each card's title and message carry the meaning) rather than collapsing them to one token and losing the at-a-glance distinction between the three cards.

- [ ] **Step 1: Restyle the Docker card**

In `OverviewView.swift`, replace `dockerCard`:

```swift
private var dockerCard: some View {
    Card {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Docker resources", systemImage: "shippingbox.fill")
                    .appFont(Typography.title)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(
                    LocalizedFormatters.text(
                        "about %@", locale: locale,
                        LocalizedFormatters.bytes(
                            model.estimatedDockerBytes, locale: locale))
                )
                .appFont(Typography.caption)
                .foregroundStyle(Theme.textSecondary)
                .monospacedDigit()
            }
            Text(
                """
                Estimated separately. Docker image layers are shared between images, so \
                removing two images does not free the sum of their sizes. Docker removals \
                cannot be undone.
                """
            )
            .appFont(Typography.body)
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)

            Button("Show Docker details") {
                coordinator.scanModel.ecosystemFilter = .docker
                coordinator.destination = .caches
            }
            .buttonStyle(.macDevSecondary)
            .accessibilityIdentifier("docker.details")
        }
    }
}
```

- [ ] **Step 2: Restyle `InfoCard`'s icon badge background/typography**

In `InfoCard.swift`:

```swift
struct InfoCard: View {
    let symbol: String
    let tint: Color
    let title: LocalizedStringKey
    let message: LocalizedStringKey

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)
                    .background(tint.opacity(0.14), in: .rect(cornerRadius: Layout.controlRadius))
                    .accessibilityHidden(true)
                Text(title)
                    .appFont(Typography.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.textPrimary)
                Text(message)
                    .appFont(Typography.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
```

- [ ] **Step 3: Build to verify it compiles**

Run: `xcodebuild -workspace MacDevClean.xcworkspace -scheme MacDevClean -destination 'platform=macOS' -derivedDataPath .build/xcode build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add MacDevCleanApp/Features/Overview/OverviewView.swift MacDevCleanApp/DesignSystem/InfoCard.swift
git commit -m "feat(overview): restyle the Docker card and info cards per the redesign spec"
```

---

## Task 6: Full-screen "never scanned" state

**Files:**
- Create: `MacDevCleanApp/Features/Overview/NeverScannedView.swift`
- Modify: `MacDevCleanApp/Features/Overview/OverviewView.swift`

**Interfaces:**
- Consumes: `Theme.textPrimary/.textSecondary/.textTertiary`, `Typography.title/.body/.caption` + `View.appFont`, `PrimaryButtonStyle`/`SecondaryButtonStyle`.
- Produces: `NeverScannedView(startScan: () -> Void, chooseFolders: () -> Void)`, a `View`. `OverviewView.body` renders it in place of the existing card layout when `!model.hasScanned && !model.isScanning`.

- [ ] **Step 1: Create `NeverScannedView`**

```swift
// MacDevCleanApp/Features/Overview/NeverScannedView.swift
import SwiftUI

/// The full-screen state shown before the first scan ever runs — spec
/// screen `1i`. Replaces the card layout entirely rather than showing an
/// empty ring, because there is nothing yet to summarize.
///
/// The message `Text` below is deliberately not `.fixedSize(vertical: true)`
/// — see `EmptyStateView.swift` and `docs/verification/10-defects.md` for
/// why that combination, at the root of the detail column, previously
/// emptied the sidebar (defect D3).
struct NeverScannedView: View {
    var startScan: () -> Void
    var chooseFolders: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Theme.textTertiary)
                .accessibilityHidden(true)
            Text("Nothing has been scanned yet")
                .appFont(Typography.title)
                .foregroundStyle(Theme.textPrimary)
            Text(
                """
                MacDevClean only reads the project folders you chose in Settings. A scan \
                measures sizes and explains what each item costs.
                """
            )
            .appFont(Typography.body)
            .foregroundStyle(Theme.textSecondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 460)

            HStack(spacing: 10) {
                Button("Scan now", action: startScan)
                    .buttonStyle(.macDevPrimary)
                    .accessibilityIdentifier("scan.start")
                Button("Choose folders…", action: chooseFolders)
                    .buttonStyle(.macDevSecondary)
            }
            .padding(.top, 2)

            Text("Scanning doesn't select or remove anything.")
                .appFont(Typography.caption)
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, minHeight: 320)
        .padding(40)
    }
}
```

- [ ] **Step 2: Wire it into `OverviewView.body`**

Change `OverviewView.body`:

```swift
var body: some View {
    ScrollView {
        if !model.hasScanned && !model.isScanning {
            NeverScannedView(
                startScan: { coordinator.startScan() },
                chooseFolders: { coordinator.destination = .settings }
            )
            .padding(Layout.contentInset)
        } else {
            VStack(alignment: .leading, spacing: Layout.cardGap) {
                header

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: Layout.cardGap) {
                        summaryColumn.frame(maxWidth: .infinity)
                        categoriesColumn.frame(maxWidth: .infinity)
                    }
                    VStack(spacing: Layout.cardGap) {
                        summaryColumn
                        categoriesColumn
                    }
                }

                if !model.dockerSummaries.isEmpty {
                    dockerCard
                }

                informationCards
            }
            .padding(Layout.contentInset)
        }
    }
    .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: model.isScanning)
    .navigationTitle(Text("Overview"))
}
```

`coordinator.destination = .settings` matches the `Destination` case already used elsewhere in this file (see `dockerCard`'s `coordinator.destination = .caches`), so "Choose folders…" routes to the existing Settings screen, which owns root folder management — there is no separate folder-picker sheet to invoke directly from Overview.

- [ ] **Step 3: Build to verify it compiles**

Run: `xcodebuild -workspace MacDevClean.xcworkspace -scheme MacDevClean -destination 'platform=macOS' -derivedDataPath .build/xcode build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add MacDevCleanApp/Features/Overview/NeverScannedView.swift MacDevCleanApp/Features/Overview/OverviewView.swift
git commit -m "feat(overview): add full-screen never-scanned state per the redesign spec"
```

---

## Task 7: Full-screen "scanning" state

**Files:**
- Create: `MacDevCleanApp/Features/Overview/ScanningStateView.swift`
- Modify: `MacDevCleanApp/Features/Overview/OverviewView.swift`

**Interfaces:**
- Consumes: `Theme.cardBackground/.cardBorder/.separator/.textPrimary/.textSecondary/.textTertiary`, `Typography.title/.body/.caption` + `View.appFont`, `SecondaryButtonStyle`, `Layout.cardRadius/.separator`.
- Produces: `ScanningStateView(visited: Int, cancel: () -> Void)`, a `View`. `OverviewView.body` renders it in place of the existing card layout when `model.isScanning`.

- [ ] **Step 1: Create `ScanningStateView`**

Per the Global Constraints note: this shows only what `ScanModel` actually provides while scanning (`visited`, an indeterminate progress bar, and cancel) — not the spec mockup's fraction, file path or partial total, none of which the domain layer produces mid-scan.

```swift
// MacDevCleanApp/Features/Overview/ScanningStateView.swift
import SwiftUI

/// The full-screen state shown while a scan is running — spec screen `1j`,
/// adapted to the data `ScanModel` actually has mid-scan (a running entry
/// count, nothing else). See the redesign-overview plan's Global
/// Constraints for why the spec's fraction/path/partial-total are not
/// reproduced here: `ScanModel` doesn't know a total until the scan ends,
/// and inventing one would misreport progress.
struct ScanningStateView: View {
    let visited: Int
    var cancel: () -> Void

    var body: some View {
        VStack(spacing: Layout.space16) {
            VStack(alignment: .leading, spacing: Layout.space16) {
                Text("Scanning project folders")
                    .appFont(Typography.title)
                    .foregroundStyle(Theme.textPrimary)

                ProgressView()
                    .progressViewStyle(.linear)
                    .accessibilityIdentifier("scan.progress")
                    .accessibilityLabel("Scanning")

                Text("\(visited) entries so far.")
                    .appFont(Typography.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .monospacedDigit()

                Divider().overlay(Theme.separator)

                HStack(spacing: Layout.space12) {
                    Button("Stop scanning", action: cancel)
                        .buttonStyle(.macDevSecondary)
                        .accessibilityIdentifier("scan.cancel")
                    Text("Stopping keeps what's already been measured and removes nothing.")
                        .appFont(Typography.caption)
                        .foregroundStyle(Theme.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(22)
            .frame(maxWidth: 520)
            .background(Theme.cardBackground, in: .rect(cornerRadius: Layout.cardRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Layout.cardRadius)
                    .strokeBorder(Theme.cardBorder, lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity, minHeight: 320)
        .padding(40)
    }
}
```

- [ ] **Step 2: Wire it into `OverviewView.body`**

Change the `else` branch added in Task 6 so scanning takes priority over the with-results layout:

```swift
if !model.hasScanned && !model.isScanning {
    NeverScannedView(
        startScan: { coordinator.startScan() },
        chooseFolders: { coordinator.destination = .settings }
    )
    .padding(Layout.contentInset)
} else if model.isScanning {
    ScanningStateView(visited: model.visited, cancel: { coordinator.cancelScan() })
        .padding(Layout.contentInset)
} else {
    VStack(alignment: .leading, spacing: Layout.cardGap) {
        // (unchanged — header, summaryColumn/categoriesColumn, dockerCard, informationCards)
    }
    .padding(Layout.contentInset)
}
```

Now that the scanning UI lives in `ScanningStateView`, remove the `if model.isScanning { ... } else { ... }` branch inside `summaryColumn` — `summaryColumn` is only ever shown once `model.isScanning` is already `false` (the `else` branch above), so `summaryColumn`'s body becomes just its former `else` contents (the ring, "Review cleanup" button, "Start scan"/"Scan again" button and `statusMessage`), unconditionally.

- [ ] **Step 3: Build to verify it compiles**

Run: `xcodebuild -workspace MacDevClean.xcworkspace -scheme MacDevClean -destination 'platform=macOS' -derivedDataPath .build/xcode build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add MacDevCleanApp/Features/Overview/ScanningStateView.swift MacDevCleanApp/Features/Overview/OverviewView.swift
git commit -m "feat(overview): add full-screen scanning state per the redesign spec"
```

---

## Task 8: Full verification, manual check, and progress record

**Files:**
- Modify: `docs/progress.md`

**Interfaces:**
- Consumes: nothing new.

- [ ] **Step 1: Run the full verification gate**

Run: `MACDEVCLEAN_SKIP_UI_TESTS=1 bash scripts/verify.sh`
Expected: exit 0. Record the actual test count, toolchain and date observed — this plan changed no test files, so the count should match the foundation plan's Task 7 evidence exactly (21 package + 83 app tests); if it doesn't, investigate before proceeding.

- [ ] **Step 2: Run the app and look at all four Overview states**

Use the `run` skill (or `open .build/xcode/Build/Products/Debug/MacDevClean.app` after the Step 1 build) to launch the app and visually confirm, in both System Settings > Appearance > Light and Dark:
- The sidebar's background, wordmark and footer match the new tokens.
- With no folders added yet (or after clearing them in Settings), the never-scanned full-screen state appears and both buttons work.
- Starting a scan shows the scanning full-screen state with a moving indeterminate bar and a live-updating entry count, and "Stop scanning" cancels it.
- After a scan completes, the with-results layout (header, ring, categories, Docker card if applicable, info cards) renders with the new colors and the restyled "Review cleanup" button.

Record what you actually saw — this project's verification convention (`docs/verification/*.md`) requires real observed evidence, never an assumed pass.

- [ ] **Step 3: Update `docs/progress.md`**

Update the "Plan status" table's `redesign foundation` row area by adding a new row directly beneath it:

```markdown
| redesign overview screen | feature/new-design | in progress — sidebar chrome and Overview's 4 states restyled |
```

Update "Current state" to point at this plan, and record the real `scripts/verify.sh` exit status and what Step 2's manual check actually showed (or didn't — e.g. if UI tests remain blocked, say so, following the existing "known blockers" convention rather than omitting it).

- [ ] **Step 4: Commit**

```bash
git add docs/progress.md
git commit -m "docs: record redesign-overview-screen verification evidence"
```

---

## Self-Review

**Spec coverage:** sidebar chrome (Task 1), header (Task 2), ring/summary card and its primary button (Task 3), categories card and row (Task 4), Docker card and info cards (Task 5), never-scanned full-screen state — screen `1i` (Task 6), scanning full-screen state — screen `1j`, adapted to real data (Task 7). Screens `1a`/`1b` (with results, light/dark) are the baseline card layout already covered by Tasks 2–5; dark mode needs no separate task because every `Theme` token already resolves for both appearances (verified by the foundation plan's `ThemeColorTests`).

**Placeholder scan:** no `TBD`/`TODO`/"handle appropriately" language. The one deliberate content gap (scanning progress fraction/path/partial total) is explained, not hand-waved, in Global Constraints and in `ScanningStateView`'s doc comment.

**Type consistency:** `NeverScannedView`'s and `ScanningStateView`'s initializer parameter types match what `OverviewView.body` passes in Tasks 6–7 (`() -> Void` closures, `Int` for `visited`). `RiskBadge`, `Theme`, `Typography`, `Layout`, and the button styles are referenced with the exact names the foundation plan (`2026-09-22-00-redesign-foundation.md`) defines.
