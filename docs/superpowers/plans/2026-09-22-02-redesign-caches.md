# Redesign Caches Screen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restyle the Caches screen (toolbar, candidate list, high-risk section, footer, and its empty/scanning states) to match the redesign spec, reusing the `Theme`/`Typography`/`Layout`/`RiskBadge`/button-style foundation and the process already used for Overview.

**Architecture:** Presentation-only changes inside `MacDevCleanApp/Features/Caches/` (`CachesView.swift`, `CandidateRow.swift`) plus the shared `EmptyStateView.swift` (used by both Caches and Overview, restyled once here so both benefit). No new files, no new full-screen state views — unlike Overview, every Caches state the spec shows already has a matching branch in the current `CachesView.body`; this plan re-skins them in place.

**Tech Stack:** Swift 6, SwiftUI.

**Spec:** [docs/references/redesign/design-tokens.md](../../references/redesign/design-tokens.md); screens `1c` (selection in progress, light, 1440×900), `1d` (nothing selected, dark, EN, 1100×720), `1k` (filters hide everything, light, 1100×720), `1l` (scan can't start, dark, 1100×720) in [docs/references/redesign/MacDevClean Redesign.dc.html](../../references/redesign/MacDevClean%20Redesign.dc.html).

## Global Constraints

Same as `docs/superpowers/plans/2026-09-22-01-redesign-overview.md`'s Global Constraints (foundation tokens only, no fake window chrome, no invented data, no `.fixedSize(vertical: true)` at the detail-column root, view bodies verified by build not unit test), plus two lessons from that plan's manual review:

- **Reuse existing catalog copy — introduce zero new strings in this plan.** Every piece of text this plan touches already has an English/Portuguese pair in `Localizable.xcstrings` (this screen adds no new full-screen state, unlike Overview's `NeverScannedView`/`ScanningStateView`). If a step is tempted to write new copy, stop and either reuse an existing key or flag it instead of guessing — the Overview plan shipped untranslated English text for exactly this reason.
- **Match the spec's concrete layout numbers, not an approximation.** The Overview plan's first pass used an equal 50/50 column split where the spec specified `minmax(0,1fr) 520px`; verify each width/ratio this plan touches against the actual spec markup before implementing, not from memory of "close enough."
- This plan changes zero test files and zero new-copy strings, so `scripts/verify.sh`'s test counts must come out identical to the Overview plan's evidence (21 package + 83 app tests) — a different count means something unexpected happened.

---

## Task 1: Restyle `EmptyStateView` (shared by Caches and Overview)

**Files:**
- Modify: `MacDevCleanApp/DesignSystem/EmptyStateView.swift`

- [ ] **Step 1: Apply Theme/Typography tokens, keeping the D3-safe layout exactly as-is**

```swift
import SwiftUI

/// The state shown when there is nothing to show, which is a result rather than
/// a failure.
struct EmptyStateView: View {
    let symbol: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    var actionTitle: LocalizedStringKey?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Theme.textTertiary)
                .accessibilityHidden(true)
            Text(title)
                .appFont(Typography.title)
                .foregroundStyle(Theme.textPrimary)
            // No `fixedSize(horizontal: false, vertical: true)` here — see
            // docs/verification/10-defects.md (defect D3). This omission is
            // deliberate and must not be reintroduced.
            Text(message)
                .appFont(Typography.body)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.macDevPrimary)
            }
        }
        .frame(maxWidth: 420)
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity)
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodebuild -workspace MacDevClean.xcworkspace -scheme MacDevClean -destination 'platform=macOS' -derivedDataPath .build/xcode build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Lint and commit**

Run: `bash scripts/lint.sh` — expect "no findings".

```bash
git add MacDevCleanApp/DesignSystem/EmptyStateView.swift
git commit -m "feat(caches): restyle shared EmptyStateView per the redesign spec"
```

---

## Task 2: Restyle the Caches toolbar

**Files:**
- Modify: `MacDevCleanApp/Features/Caches/CachesView.swift`

- [ ] **Step 1: Restyle the filter labels and selection buttons**

In `filters`, style each `Picker`'s inline label via a wrapping `HStack` (SwiftUI `Picker` doesn't expose its label's font/color independently, so this adds the spec's `--tx2` label ahead of the system control rather than fighting the control's own chrome):

```swift
@ViewBuilder
private var filters: some View {
    Group {
        labeledFilter("Ecosystem") {
            Picker("Ecosystem", selection: $model.ecosystemFilter) {
                Text("All ecosystems").tag(CleanupCategory?.none)
                ForEach(availableCategories, id: \.self) { category in
                    Text(CategoryNaming.title(category)).tag(CleanupCategory?.some(category))
                }
            }
            .labelsHidden()
            .frame(maxWidth: 260)
            .accessibilityIdentifier("filter.ecosystem")
        }

        labeledFilter("Risk") {
            Picker("Risk", selection: $model.riskFilter) {
                Text("Any risk").tag(RiskLevel?.none)
                ForEach(RiskLevel.allCases, id: \.self) { risk in
                    Text(RiskBadge.title(risk)).tag(RiskLevel?.some(risk))
                }
            }
            .labelsHidden()
            .frame(maxWidth: 180)
            .accessibilityIdentifier("filter.risk")
        }

        labeledFilter("Sort") {
            Picker("Sort", selection: $model.sort) {
                Text("Largest first").tag(ScanModel.Sort.size)
                Text("By name").tag(ScanModel.Sort.name)
            }
            .labelsHidden()
            .frame(maxWidth: 170)
            .accessibilityIdentifier("filter.sort")
        }
    }
}

private func labeledFilter<Content: View>(
    _ label: LocalizedStringKey, @ViewBuilder content: () -> Content
) -> some View {
    HStack(spacing: 7) {
        Text(label)
            .appFont(Typography.caption)
            .foregroundStyle(Theme.textSecondary)
        content()
    }
}
```

Restyle `selectionButtons` with the secondary button style:

```swift
@ViewBuilder
private var selectionButtons: some View {
    Button("Select all low and medium risk") { model.selectAllSelectable() }
        .buttonStyle(.macDevSecondary)
        .accessibilityIdentifier("selection.selectAll")
    Button("Clear selection") { model.clearSelection() }
        .buttonStyle(.macDevSecondary)
        .disabled(model.selectedIDs.isEmpty)
        .accessibilityIdentifier("selection.clear")
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodebuild -workspace MacDevClean.xcworkspace -scheme MacDevClean -destination 'platform=macOS' -derivedDataPath .build/xcode build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Lint and commit**

```bash
git add MacDevCleanApp/Features/Caches/CachesView.swift
git commit -m "feat(caches): restyle the filter toolbar per the redesign spec"
```

---

## Task 3: Restyle the candidate list card and row

**Files:**
- Modify: `MacDevCleanApp/Features/Caches/CandidateRow.swift`

- [ ] **Step 1: Restyle `CandidateRow`**

```swift
var body: some View {
    HStack(spacing: 12) {
        Toggle(isOn: Binding(get: { isSelected }, set: { _ in onToggle() })) {
            EmptyView()
        }
        .toggleStyle(.checkbox)
        .labelsHidden()
        .disabled(!isSelectable)
        .accessibilityIdentifier(ScanModel.accessibilityID(candidate))
        .accessibilityLabel("Select \(ScanModel.displayName(candidate))")

        VStack(alignment: .leading, spacing: 3) {
            Text(ScanModel.displayName(candidate))
                .appFont(Typography.body)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(ConsequenceCopy.text(for: candidate.consequenceKey))
                .appFont(Typography.caption)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            if candidate.method != .trash {
                Text("Cannot be undone")
                    .appFont(Typography.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.danger)
            }
        }

        Spacer(minLength: 12)

        VStack(alignment: .trailing, spacing: 2) {
            ByteLabel(bytes: candidate.size, style: .callout)
                .foregroundStyle(Theme.textPrimary)
            RiskBadge(risk: candidate.risk)
        }
    }
    .padding(.vertical, 8)
    .frame(minHeight: Layout.rowMinimumHeight)
    .contextMenu {
        if let onReveal, case .file = candidate.location {
            Button("Reveal in Finder", action: onReveal)
        }
        if let onExclude {
            Button("Always skip this", action: onExclude)
        }
    }
}
```

(`ConsequenceCopy` below is unchanged — it's a separate, existing latent locale bug, same class as the one already fixed in `RiskBadge.title`, but out of scope for this visual-only plan; flag it separately rather than fixing it here.)

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodebuild -workspace MacDevClean.xcworkspace -scheme MacDevClean -destination 'platform=macOS' -derivedDataPath .build/xcode build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Lint and commit**

```bash
git add MacDevCleanApp/Features/Caches/CandidateRow.swift
git commit -m "feat(caches): restyle CandidateRow per the redesign spec"
```

---

## Task 4: Restyle the high-risk section and footer

**Files:**
- Modify: `MacDevCleanApp/Features/Caches/CachesView.swift`

- [ ] **Step 1: Restyle `highRiskSection`**

```swift
private var highRiskSection: some View {
    Card {
        VStack(alignment: .leading, spacing: 10) {
            Label(
                "High risk — open to review individually",
                systemImage: "exclamationmark.circle"
            )
            .appFont(Typography.title)
            .foregroundStyle(Theme.danger)

            Text(
                """
                These may hold data that exists nowhere else. Nothing here is selected for \
                you, and bulk selection never touches it.
                """
            )
            .appFont(Typography.body)
            .foregroundStyle(Theme.textSecondary)
            // No fixedSize here: see EmptyStateView / docs/verification/10-defects.md.

            ForEach(highRiskCategories, id: \.self) { category in
                DisclosureGroup(
                    isExpanded: Binding(
                        get: { model.expandedHighRisk.contains(category) },
                        set: { expanded in
                            if expanded {
                                model.expandedHighRisk.insert(category)
                            } else {
                                model.expandedHighRisk.remove(category)
                                for item in highRisk where item.category == category {
                                    model.selectedIDs.remove(item.id)
                                }
                            }
                        }
                    )
                ) {
                    ForEach(highRisk.filter { $0.category == category }) { candidate in
                        CandidateRow(
                            candidate: candidate,
                            isSelected: model.isSelected(candidate.id),
                            isSelectable: model.expandedHighRisk.contains(category),
                            onToggle: { model.toggle(candidate) },
                            onReveal: {
                                if case .file(let url) = candidate.location {
                                    coordinator.reveal(url)
                                }
                            }
                        )
                        .accessibilityIdentifier(
                            "\(highRiskIdentifier(candidate)).select")
                    }
                } label: {
                    HStack {
                        Text(CategoryNaming.title(category))
                            .appFont(Typography.body)
                            .fontWeight(.medium)
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                        CountText(
                            "%lld item",
                            highRisk.filter { $0.category == category }.count
                        )
                        .appFont(Typography.caption)
                        .foregroundStyle(Theme.textTertiary)
                    }
                }
                .accessibilityIdentifier(Self.disclosureIdentifier(for: category, in: highRisk))
            }
        }
    }
}
```

(Icon changed from `exclamationmark.octagon` to `exclamationmark.circle` to match the spec's high-risk shape — the same change already made to `RiskBadge.symbol(.high)` in the foundation plan, kept consistent here.)

- [ ] **Step 2: Restyle `footer`**

```swift
private var footer: some View {
    HStack(spacing: 16) {
        VStack(alignment: .leading, spacing: 2) {
            CountText("%lld item selected", model.selectedIDs.count)
                .appFont(Typography.body)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.textPrimary)
                .monospacedDigit()
                .accessibilityIdentifier("selection.count")
            Text(
                LocalizedFormatters.text(
                    """
                    About %@ will move to the Trash. That frees space only when you \
                    empty it.
                    """,
                    locale: locale,
                    LocalizedFormatters.bytes(model.selectedKnownBytes, locale: locale))
            )
            .appFont(Typography.caption)
            .foregroundStyle(Theme.textSecondary)
        }

        Spacer()

        Button {
            coordinator.openReview()
        } label: {
            CountText("Review %lld selected", model.selectedIDs.count)
        }
        .buttonStyle(.macDevPrimary)
        .disabled(model.selectedIDs.isEmpty)
        .accessibilityIdentifier("cleanup.review")
    }
    .padding(.horizontal, Layout.contentInset)
    .padding(.vertical, 14)
    .background(Theme.sidebarBackground)
}
```

The `.background(Theme.sidebarBackground)` matches the spec's footer, which uses the same `--side` token as the sidebar (a visually distinct "action bar" surface, not the content background).

- [ ] **Step 3: Build to verify it compiles**

Run: `xcodebuild -workspace MacDevClean.xcworkspace -scheme MacDevClean -destination 'platform=macOS' -derivedDataPath .build/xcode build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Lint and commit**

```bash
git add MacDevCleanApp/Features/Caches/CachesView.swift
git commit -m "feat(caches): restyle the high-risk section and footer per the redesign spec"
```

---

## Task 5: Restyle the scanning and toolbar-header states

**Files:**
- Modify: `MacDevCleanApp/Features/Caches/CachesView.swift`

- [ ] **Step 1: Restyle `scanningState` and the top header bar's "Rescan" button**

```swift
private var scanningState: some View {
    VStack(spacing: 12) {
        ProgressView()
            .controlSize(.large)
            .accessibilityHidden(true)
        Text("Scanning")
            .appFont(Typography.title)
            .foregroundStyle(Theme.textPrimary)
        CountText("Looking through your folders. %lld entries so far.", model.visited)
            .appFont(Typography.caption)
            .foregroundStyle(Theme.textSecondary)
            .monospacedDigit()
            .accessibilityIdentifier("caches.scanProgress")
        Button("Stop scanning") { coordinator.cancelScan() }
            .buttonStyle(.macDevSecondary)
            .accessibilityIdentifier("caches.cancelScan")
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 40)
}
```

- [ ] **Step 2: Restyle `emptyState`**

```swift
@ViewBuilder
private var emptyState: some View {
    VStack(spacing: 10) {
        EmptyStateView(
            symbol: "tray",
            title: model.hasScanned ? "Nothing found" : "No results yet",
            message: model.hasScanned
                ? "MacDevClean found no removable artifacts in the folders you added."
                : "Run a scan from the Overview to see what is taking up space."
        )

        if !model.hasScanned {
            Button("Start scan") { coordinator.startScan() }
                .buttonStyle(.macDevPrimary)
                .disabled(coordinator.scanUnavailableReason != nil)
                .accessibilityIdentifier("caches.startScan")

            if let reason = coordinator.scanUnavailableReason {
                VStack(spacing: 6) {
                    Text(Self.explanation(for: reason))
                        .appFont(Typography.body)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("caches.scanUnavailable")

                    if reason == .noRoots {
                        Button("Add folders in Settings") {
                            coordinator.destination = .settings
                        }
                        .buttonStyle(.macDevSecondary)
                        .accessibilityIdentifier("caches.addFolders")
                    }
                }
                .frame(maxWidth: 420)
            }
        }
    }
}
```

- [ ] **Step 3: Build to verify it compiles**

Run: `xcodebuild -workspace MacDevClean.xcworkspace -scheme MacDevClean -destination 'platform=macOS' -derivedDataPath .build/xcode build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Lint and commit**

```bash
git add MacDevCleanApp/Features/Caches/CachesView.swift
git commit -m "feat(caches): restyle scanning and empty states per the redesign spec"
```

---

## Task 6: Full verification, manual check, and progress record

**Files:**
- Modify: `docs/progress.md`

- [ ] **Step 1: Run the full verification gate**

Run: `MACDEVCLEAN_SKIP_UI_TESTS=1 bash scripts/verify.sh`
Expected: exit 0, 21 package tests + 83 app tests (identical to the Overview plan's evidence — this plan added no test files and no new catalog entries).

- [ ] **Step 2: Launch the built app and ask the owner to check the Caches screen**

This session has no screenshot/GUI-driving tool for macOS apps (documented blocker, same as the Overview plan) — launch the build and ask the owner to look, rather than asserting an unverified pass:

```bash
pkill -x MacDevClean 2>/dev/null; sleep 0.5
open .build/xcode/Build/Products/Debug/MacDevClean.app
```

Ask the owner to check, in both Light and Dark: the filter toolbar, a populated candidate list with the high-risk disclosure closed, the footer's selection summary and Review button, and (if reachable) the scanning and no-results states. Record what they actually report — fix anything they flag before this task's evidence counts as done.

- [ ] **Step 3: Update `docs/progress.md`**

Add to "Plan status":

```markdown
| redesign caches screen | feature/new-design | complete (commits landed directly on this branch) — toolbar, list, high-risk section, footer |
```

Update "Current state" to point at this plan and record the real `scripts/verify.sh` result, the date, and what the owner's manual check showed (or any corrections it triggered) — following the exact pattern the Overview plan's Task 8 used.

- [ ] **Step 4: Commit**

```bash
git add docs/progress.md
git commit -m "docs: record redesign-caches-screen verification evidence"
```

---

## Self-Review

**Spec coverage:** toolbar (Task 2), candidate row (Task 3), high-risk section and footer (Task 4), scanning/empty states (Task 5), plus the shared `EmptyStateView` both this screen and Overview depend on (Task 1). Screens `1c`/`1d` (populated, light/dark) are the baseline list layout Tasks 2–4 cover; `1k` (filters hide everything) is the existing `hasResultsHiddenByFilters` branch, already using `EmptyStateView` (Task 1 covers its restyle; the spec's second "Ajustar risco" button is not added — no existing state binding lets a view open a specific picker programmatically, and adding one is a behavior change out of this plan's presentation-only scope); `1l` (scan can't start) is `emptyState`'s `!model.hasScanned` branch (Task 5).

**Placeholder scan:** no `TBD`/`TODO`. The one scope exclusion (the second filter-adjusting button on the filtered-empty state) is explained, not hand-waved.

**Type consistency:** every `Theme`/`Typography`/`Layout`/button-style reference matches the names the foundation plan defines; no task introduces a new public type or changes an existing one's signature.
