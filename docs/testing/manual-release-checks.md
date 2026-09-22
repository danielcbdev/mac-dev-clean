# Manual release checks

Checks that no automated suite in this repository performs. Each one needs a
logged-in macOS session, real hardware, or credentials that are not configured
here. **None of them has been performed.** This file is the list of what a
person must do before MacDevClean is released, and a record of why each item
cannot be satisfied by the local gate.

Related evidence: [accessibility.md](accessibility.md) for what the
accessibility work covers automatically, [performance.md](performance.md) for
what the scan benchmarks actually measure, and `docs/verification/` for the
gate results of every milestone.

## 1. Interface behaviour under XCUITest

The UI suite compiles and has never run. See
[docs/verification/05-interface.md](../verification/05-interface.md) for the
investigation.

| Check | Status |
|---|---|
| `MacDevCleanUITests` passes in a logged-in session | **Not run** |
| Overview, Caches, Large Files, History, Exclusions and Settings reachable by keyboard alone | **Not run** |
| Escape dismisses the review sheet and never starts a cleanup | **Not run** |
| Space activates a candidate checkbox and the review action | **Not run** |

## 2. VoiceOver and assistive technology

Run with VoiceOver enabled and confirm each item is spoken, not merely present.

- The Potential cleanup ring announces its total, its largest categories and the
  count of items whose size could not be measured.
- Every risk badge announces a word, not only a colour.
- A cleanup refusal moves focus to the explanation.
- Progress is announced at coarse intervals, never once per file.
- The irreversible Docker confirmation is announced in full before its button.

## 3. Appearance, contrast and motion

Inspect in both languages, with the window at its 1100×720 minimum.

- Light and dark appearance.
- Increase Contrast and Reduce Transparency: the ring must stay legible with its
  opaque fallback.
- Reduce Motion: no state-transition animation and no decorative spinner.
- Large accessibility text sizes: warnings wrap instead of truncating, and the
  footer actions stay reachable.

Screenshots belong in `docs/demo/` and must be taken from the fixture
composition, never from a real machine's caches.

## 4. Live performance

Measured while a 100,000-entry scan is active, per plan 08 Task 3:

- p50 and p95 navigation response.
- Cancellation latency.
- Peak memory.
- Completion throughput for the full 100,000 entries.

The package tests prove cancellation stops reading further batches. They do not
measure any of the above, and no number here may be quoted from them.

## 5. Real cleanup behaviour

Never on the developer's own machine, and never on real data.

- A disposable macOS account with a synthetic project tree.
- Confirm items land in that account's Trash and that MacDevClean never empties
  it.
- Confirm Docker operations only touch resources reviewed in the confirmation
  sheet, against a disposable Docker environment. **Real Docker requires the
  owner's specific authorization**; it has not been granted.

## 6. Distribution

Owned by plan 09; every item needs credentials or hardware that is not present.

| Check | Blocking requirement |
|---|---|
| Developer ID signing | Apple Developer account and certificate |
| Notarization accepted | App Store Connect API key |
| Stapled DMG launches after a quarantined download | A second, clean test Mac |
| Cask install and uninstall | A published release URL and checksum |
| Uninstall leaves history, caches and projects untouched | Disposable test account |
| Minimum supported OS (macOS 14) actually launches | A macOS 14 machine; only macOS 27.0 was available |
| Intel hardware smoke test | An Intel Mac; only Apple Silicon was available |

A build that compiles for `x86_64` is a compilation fact. It is not evidence
that the application runs on Intel hardware, and this repository never states
otherwise.
