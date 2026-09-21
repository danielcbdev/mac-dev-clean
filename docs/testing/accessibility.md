# Accessibility evidence

## Automated coverage

- `LocalizationUITests` launches the fixture scenario in English and Brazilian
  Portuguese and asserts the Overview review action label in both languages.
- `AccessibilityUITests` exercises Space-key activation for a candidate and the
  review action, using stable accessibility identifiers.

On 2026-09-21 a direct `xcodebuild` UI-test attempt built and launched the
runner. Five independent test launches then failed because the expected
`scan.start` accessibility element never appeared; the run was interrupted
after 104 seconds rather than spending more time on identical failures. The
test runner's app process still does not expose its window to XCUITest, so the
suite is **not passed** and is not counted as run evidence.

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

## Limited manual inspection

On 2026-09-21 the ad-hoc signed Debug application was opened normally, outside
XCUITest. Its application window and accessibility tree were available. In the
Brazilian Portuguese system locale, the Overview, Caches, and Settings screens
showed their semantic controls, localized labels, cache filters, disabled
cleanup actions with no selection, and language/appearance controls. No scan,
cleanup, settings change, dark-mode check, VoiceOver test, or screenshot was
performed. This confirms only normal-launch accessibility exposure; it does
not make the XCUITest result a pass or replace the pending manual checks.
