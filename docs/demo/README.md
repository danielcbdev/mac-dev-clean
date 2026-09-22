# Demo material

**This directory contains no screenshots, and none are fabricated.**

Screenshots of MacDevClean must come from the fixture composition, never from a
real machine. The fixture build creates a temporary tree of synthetic artifacts,
points `HOME` at it, and runs the real scanner over it, so a screenshot cannot
leak a real path, a real project name or a real cache.

## Why there are none

The screenshot tests live in `MacDevCleanUITests`. That suite compiles and has
never run on this machine: launched by XCUITest, the application exposes no
window to the accessibility interface, so every element query fails. The
investigation is recorded in
[docs/verification/05-interface.md](../verification/05-interface.md).

Screen capture on the development machine also requires a permission that this
session does not have.

## How to produce them

On a machine where the UI suite runs:

```bash
xcodebuild -workspace MacDevClean.xcworkspace -scheme MacDevClean \
  -destination 'platform=macOS' -derivedDataPath .build/xcode \
  -only-testing:MacDevCleanUITests test
```

Then, for each of light and dark appearance, English and Brazilian Portuguese,
and the 1100×720 minimum window, capture:

| File | Screen | What it must show |
|---|---|---|
| `overview-{en,pt-BR}-{light,dark}.png` | Overview | The summary ring with its total, the category rows with risk badges, and the three footer cards |
| `caches-{en,pt-BR}.png` | Caches | High-risk items behind their disclosure, not selectable from the list |
| `review-{en,pt-BR}.png` | Review | The full irreversible warning, wrapped rather than truncated, with the footer actions reachable |
| `results-{en,pt-BR}.png` | Results | Bytes moved to the Trash, Docker's reported reclaim and the observed free-space change as three separate figures |
| `large-files-{en,pt-BR}.png` | Large Files | Nothing preselected, and a symbolic link shown as informational |

Launch arguments for the fixture composition:

```text
--ui-testing --scenario mixed-results -AppleLanguages (pt-BR) -AppleLocale pt_BR
```

Check before committing any image: no real path, no real project name, no user
name in a window title, and no real Docker resource identifier.

## The icon

The application icon is generated, not photographed, and is original work:

```bash
swift scripts/make-appicon.swift \
    MacDevCleanApp/Resources/Assets.xcassets/AppIcon.appiconset
```
