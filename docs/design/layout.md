# Interface layout

What was built, measured against
[the approved reference](../references/macdevclean-ui-reference.png), and every
place the implementation deliberately departs from it.

## Structure

| Component | Implementation |
|---|---|
| Window | minimum 1100×720 pt, default 1280×840, `windowResizability(.contentMinSize)`; content scrolls vertically |
| Sidebar | `navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)`, native traffic lights, MacDevClean title and tagline, six destinations, a standing reminder in the footer |
| Content | 28 pt inset, 20 pt gaps between cards |
| Overview columns | summary and categories side by side, wrapped in `ViewThatFits` so they stack rather than truncate at large text sizes |
| Summary ring | 220–280 pt, 18 pt stroke, total centred, one coloured segment per category |
| Category row | minimum 64 pt, 40 pt symbol tile, two-line label, trailing size, risk badge and disclosure |
| Information cards | three equal cards, stacking through `ViewThatFits` when they would not fit |
| Card style | semantic background, 1 pt separator border, 12 pt radius, no heavy shadow |
| Text | system styles throughout; every number uses `monospacedDigit`; no fixed-height text boxes, and long copy uses `fixedSize(horizontal: false, vertical: true)` so it wraps instead of truncating |

The layout uses no fixed heights for text and no hard-coded English widths, so
Brazilian Portuguese — reliably longer — pushes layout down rather than clipping
it.

## Where this departs from the reference, and why

The reference is a visual direction, not a specification of claims. Four of its
statements are not true of this product, so the implementation says something
else.

| Reference | Implementation | Reason |
|---|---|---|
| "42.8 GB **reclaimable**" | "**Potential cleanup**", with a tooltip | An item the app relocates still occupies the volume until the user clears it in Finder, so calling the figure reclaimable would be false. |
| Ring implies a proportion of the disk | Denominator is the **sum of known filesystem candidate sizes** | A ring measured against the whole disk would imply a proportion nobody computed. |
| "**Reclaim performance** — a cleaner system can speed up builds" | "**Know the impact** — a cache that is cleared gets rebuilt; the next build is slower, not faster" | The original claim is backwards. |
| "Safe cleanup — only removes cache files" | "**Trash first** — the system Trash API handles every filesystem item" | Nothing here is guaranteed safe, and Docker operations are not recoverable at all. |
| Docker shown as one more category in the same total | Docker has its **own card and its own subtotal** | Image layers are shared, so Docker bytes cannot be added to filesystem bytes without misrepresenting both. |

The three footer cards are "Trash first", "Know the impact" and "You stay in
control", replacing the reference's "Safe by default", "Reclaim performance" and
"Your time matters".

The application name is MacDevClean everywhere. The reference image shows an
earlier name.

## Risk, and the refusal to say "safe"

`RiskBadge` renders an SF Symbol, a word and a colour together:

| Level | Symbol | Word |
|---|---|---|
| Low | `checkmark.shield` | "Low risk" |
| Medium | `exclamationmark.triangle` | "Medium risk" |
| High | `exclamationmark.octagon` | "High risk" |

Colour never carries meaning alone — the word is always present, so the badge
survives a monochrome screenshot, Increase Contrast, and colour vision
deficiency. Nothing anywhere is labelled "guaranteed safe": the lowest level is
"Low risk".

## Selection rules expressed in the layout

- A scan selects nothing. The footer reads "0 items selected" until the user
  acts.
- High-risk items are **not selectable from the list**. They live behind a
  disclosure the user opens deliberately, and closing it clears those
  selections.
- "Select all low and medium risk" never reaches a high-risk row, and the button
  says so in its title rather than in a footnote.
- Filters change what is shown, never what is selected. A selection made under
  one filter survives switching to another.
- The primary action names exactly what it will do, never "Continue".

## Accessibility

- The ring is an accessibility element with a textual value listing the total,
  the largest categories and the count of unmeasurable items, because a chart
  without a textual equivalent is unreadable to a screen reader.
- Every icon-only control has a label. Decorative symbols are hidden from
  assistive technology.
- Category and candidate rows expose a composed label: name, size, risk.
- Sizes are announced as "Size could not be measured" rather than as silence.
- Automation identifiers are stable and derived from rule identifiers, never
  from paths, so no test or screenshot can leak a real location.

## Known gaps at this milestone

- **Large Files, History, Exclusions and Settings are placeholders.** They state
  plainly that the feature is not built yet rather than showing an empty list,
  which would read as "you have no history" when the truth is "no history is
  being kept". They are owned by plans 06 and 07.
- **Cleanup is disabled in the release composition** until a durable journal
  exists, and the review screen explains that. The fixture composition used by
  UI automation enables it against fake adapters.
- **No screenshots are included yet.** They belong with the localisation and
  accessibility work in plan 08, and must be taken from fixture data.
