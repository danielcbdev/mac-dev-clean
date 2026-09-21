# Persistence and Management Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Store preferences, roots, exclusions and cleanup history locally and expose their management screens.

**Architecture:** One model actor implements Domain repository protocols; features see Sendable snapshots only. The journal writes pending state before effects.

**Tech Stack:** SwiftData, Foundation Codable, Observation, SwiftUI, XCTest.

**Spec:** [Approved specification](../specs/2026-09-21-macdevclean-design.md); [contracts](../specs/2026-09-21-interface-contracts.md).

## Global Constraints

- Product: MacDevClean; desktop application from the first runnable milestone.
- Swift 6 language mode; deployment target macOS 14; Xcode 16 or newer, with the exact tested Xcode build recorded.
- UI: English and Brazilian Portuguese; source, commits, technical documentation: English.
- SwiftUI, Observation, structured Swift Concurrency, Foundation, SwiftData and XCTest.
- No production runtime dependencies outside Apple frameworks; any build tooling dependency requires an ADR.
- No sandbox, privileged helper, administrator prompt, telemetry, server, scheduled deletion or background agent.
- Filesystem cleanup is Trash-only; no permanent filesystem deletion or empty-Trash command.
- Docker writes require a confirmed immutable selection, local endpoint verification and typed allowlisted commands.
- Tests operate on owned synthetic fixtures and fake destructive adapters; never on user caches, real Trash or existing Docker resources.
- Follow the approved spec plus the documented technical clarifications in docs/superpowers/specs/2026-09-21-implementation-clarifications.md.
- Do not publish, create remote repositories or upload artifacts without explicit authorization; local branches, commits and merges are authorized.

## Review Focus

- A crash between removal and journal completion must become indeterminate: Task 1.
- A corrupt database must never be silently discarded: Task 1.
- Retention must not remove unfinished sessions: Task 1.
- An exclusion save failure must not appear protected in the UI: Task 2.
- A Trash URL deleted externally must hide the reveal action gracefully: Task 2.

---

## Scope and files

Prerequisites: plans 03, 05, 06. Branch: feat/history-and-exclusions.

Create under Packages/MacDevCleanCore:
- Sources/Persistence/{SchemaV1,MigrationPlan,StoredPreferences,StoredRoot,StoredExclusion,StoredSession,StoredRecord,SwiftDataRepositories}.swift.
- Tests/PersistenceTests/{PreferencesTests,JournalPersistenceTests,RetentionTests}.swift.

Create app features:
- Features/History/{HistoryView,HistoryModel,HistoryDetailView}.swift.
- Features/Exclusions/{ExclusionsView,ExclusionsModel}.swift.
- Features/Settings/{SettingsView,SettingsModel}.swift.
- MacDevCleanAppTests/RepositoryWiringTests.swift; MacDevCleanUITests/HistorySettingsUITests.swift.
- docs/adr/0005-local-persistence.md; docs/verification/07-persistence.md.
Modify AppDependencies to use durable repositories, AppSafetyContextProvider to publish policy revisions, app termination handling and localization.

### Task 1: Isolated durable repositories and interrupted-session recovery

**Files:** Packages/MacDevCleanCore/Sources/Persistence/{SchemaV1,MigrationPlan,StoredPreferences,StoredRoot,StoredExclusion,StoredSession,StoredRecord,SwiftDataRepositories}.swift, Tests/PersistenceTests/{PreferencesTests,JournalPersistenceTests,RetentionTests}.swift (package-relative); docs/adr/0005-local-persistence.md.

**Interfaces:** SwiftDataRepositories implements SettingsRepository and HistoryRepository. Factory make(containerURL: URL?, inMemory: Bool) throws -> SwiftDataRepositories returns a model-actor backed repository. nil URL only valid with inMemory true; production composition passes explicit Application Support/MacDevClean/store.sqlite URL. No ModelContext crosses actor boundaries.

- [ ] Write in-memory repository test:
```swift
func testPreferencesRoundTrip() async throws {
    let repository = try SwiftDataRepositories.make(containerURL: nil, inMemory: true)
    var preferences = AppPreferences()
    preferences.language = .portugueseBrazil
    preferences.scanOnLaunch = true
    try await repository.savePreferences(preferences)
    let restored = try await repository.preferences()
    XCTAssertEqual(restored, preferences)
}
```
Add file-backed reopen test in FixtureTree: roots/exclusions/history survive a fresh container. Test journal begin creates pending records; interrupted reopening yields indeterminate, never removed. Add retention boundary exactly 30 days, unfinished sessions preserved, clear history leaves preferences/exclusions untouched.
- [ ] Run `swift test --package-path Packages/MacDevCleanCore --filter PersistenceTests` red.
- [ ] Implement VersionedSchema SchemaV1 and SchemaMigrationPlan with V1 listed and no fabricated future migrations. Stored records use UUID, date, raw enums and bounded encoded candidate payloads; explicit validation on decode. Use @ModelActor or equivalent actor confinement:
```swift
public func savePreferences(_ value: AppPreferences) async throws {
    let data = try JSONEncoder().encode(value)
    let row = try preferenceRow()
    row.payload = data
    try modelContext.save()
}
```
preferenceRow() fetches singleton by fixed key, creates only if absent; all writes use explicit save. History aggregate IDs immutable; uniqueness enforced, duplicate begin fails instead of resetting progress. Do not allow arbitrary Codable enum unknowns to cause deletion of stored data.
- [ ] Simulate corrupt store and unavailable disk; fail with a recoverable settings error and disable cleanup if journal cannot persist. Never silently erase or recreate a corrupt database. For corrupt single records preserve row and show unreadable entry while other history loads.
- [ ] Implement recoverInterruptedSessions: pending outcomes -> indeterminate with code session.interrupted, no filesystem/Docker commands. Retention deletes only completed sessions older than cutoff; no automatic file/Trash effect. Re-run tests and commit:
```bash
git add Packages docs
git commit -m "feat: persist settings and write-ahead cleanup history locally"
```

### Task 2: Exclusions, settings and history screens

**Files:** MacDevCleanApp/Features/History/{HistoryView,HistoryModel,HistoryDetailView}.swift, Features/Exclusions/{ExclusionsView,ExclusionsModel}.swift, Features/Settings/{SettingsView,SettingsModel}.swift, App/{AppDependencies,AppSafetyContextProvider}.swift, MacDevCleanAppTests/RepositoryWiringTests.swift (app-relative); MacDevCleanUITests/HistorySettingsUITests.swift.

**Interfaces:** HistoryModel(repository:workspace:files:) exposes sessions, load() async, clearConfirmed() async, revealTrash(recordID:) async. SettingsModel(repository:context:) exposes preferences/roots and save() async. ExclusionsModel(repository:context:picker:) exposes exclusions, add(_:) async and remove(_:) async. Methods update policy revision and invalidate snapshots when roots/exclusions change. A running cleanup sees latest revision before its next item.

- [ ] Add UI flow test:
```swift
func testAddingExclusionInvalidatesSelection() {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-testing", "--scenario", "mixed-results"]
    app.launch()
    app.buttons["sidebar.caches"].click()
    app.checkBoxes["candidate.node-fixture.select"].click()
    app.buttons["candidate.node-fixture.exclude"].click()
    XCTAssertFalse(app.buttons["cleanup.review"].isEnabled)
    app.buttons["sidebar.exclusions"].click()
    XCTAssertTrue(app.staticTexts["exclusion.fixture"].exists)
}
```
Also test missing exclusion path remains with “Unavailable”; clearing history requires confirmation and never invokes TrashClient; Show in Trash absent when URL disappeared; language/appearance persist; scan-on-launch only after roots exist and is explicitly enabled.
- [ ] Run UI/model tests red. Implement History list with date/count/outcome summary; detail rows with category, original location, risk, method and safe error. “Show in Trash” checks current URL existence and reveals it via WorkspaceOpening; “Open Trash” remains independent. Show interrupted as unknown outcome, not failure/retry.
- [ ] Exclusions screen: add path via picker, category via menu, rule via registered rule list; remove confirmation for protected selections, show unavailable rows. Do not lower-case paths indiscriminately; use persisted normalized URLs and live filesystem policy.
- [ ] Settings screen: root list/edit, scan-on-launch off, threshold presets, language system/en/pt-BR, appearance system/light/dark, retention forever/30/90, version/about/licenses/privacy. Keep semantic enum values in persistence rather than translated strings.
```swift
try await repository.saveExclusions(updated)
await context.invalidateAfterSettingsChange()
```
Define AppSafetyContextProvider.invalidateAfterSettingsChange() async to increment revision and call CandidateStore.invalidate; context.current derives a consistent settings snapshot. If save fails do not pretend the exclusion is active; reflect error and retain prior context.
- [ ] Implement local privacy-safe Logger messages and diagnostic export test excluding real home prefix, test secrets, volume names and stdout. Add an offline smoke test disabling Docker; no network features required. Full verify.sh, commit, merge:
```bash
git add MacDevCleanApp MacDevCleanUITests Packages docs
git commit -m "feat: manage exclusions preferences and auditable history"
```

## Exit gate

A relaunch preserves settings/history; interrupted sessions remain uncertain; corrupt storage does not vanish; exclusion edits immediately revoke stale authority; history actions cannot delete user files. Production cleanup uses durable journal, not preview storage.
