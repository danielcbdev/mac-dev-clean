# Accessibility evidence

## Automated coverage

- `LocalizationUITests` launches the fixture scenario in English and Brazilian
  Portuguese and asserts the Overview review action label in both languages.
- `AccessibilityUITests` exercises Space-key activation for a candidate and the
  review action, using stable accessibility identifiers.

On 2026-09-21 the UI test invocation was started locally but did not deliver
results: the runner exited while `xcodebuild` continued waiting for the
accessibility interface. The process was stopped after the same unavailable
UI-gate symptom recorded for plans 05–07. These UI tests compile but are **not
run** and are not treated as passing evidence.

## Manual checks

The following checks remain pending a logged-in macOS session in which
XCUITest can observe the app window:

- VoiceOver reads the Potential cleanup summary, each risk label, scan status,
  review warning, and irreversible confirmation controls.
- Light and dark fixture screenshots in English and Brazilian Portuguese at
  the 1100×720 minimum window show no clipped warning or unreachable footer.
- Increase Contrast and Reduce Transparency keep the storage ring legible.
- Reduce Motion suppresses the Overview state-transition animation.

No screenshots were captured in this environment, so none are claimed as
evidence. The implementation uses semantic colors, scrollable screen content,
and an opaque ring fallback when Reduce Transparency is enabled.
