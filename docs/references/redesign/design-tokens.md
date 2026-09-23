# Redesign design tokens

Distilled from `MacDevClean Redesign.dc.html` (Claude Design project
`a6857bb9-3af3-44bf-860e-d04ab0608f85`, file `MacDevClean Redesign.dc.html`,
downloaded 2026-09-22). That file is the source of truth; this table exists so
implementers don't have to re-parse 150KB of inline-styled markup to find a
hex value. Verified identical across all 13 screen frames (`1a`–`1m`) — every
light frame declares the same 22 custom properties with the same light
values, every dark frame the same dark values.

The `sys` block in the spec (a palette-swatch demo) renders from a template
loop with no bound data, so it carries no real hex values — the frame-root
`style="--token:#hex;..."` attributes on screens `1a`–`1m` are the only
authoritative source for colors.

## Color tokens

| Token | Light | Dark | Notes |
|---|---|---|---|
| `--bg` (background) | `#FFFFFF` | `#1C1C1E` | window/content background |
| `--side` (sidebarBackground) | `#EDEDF0` | `#252528` | |
| `--card` (cardBackground) | `#F7F7F9` | `#232326` | |
| `--bd` (cardBorder) | `rgba(0,0,0,.09)` | `rgba(255,255,255,.12)` | card border, not a solid hex |
| `--sep` (separator) | `#E3E3E7` | `#3A3A3E` | |
| `--tx` (textPrimary) | `#1D1D1F` | `#F2F2F5` | |
| `--tx2` (textSecondary) | `#5F5F66` | `#A6A6AC` | |
| `--tx3` (textTertiary) | `#76767C` | `#98989E` | |
| `--acFill` (accentFill) | `#1565E0` | `#3D8CF5` | primary button fill, active nav |
| `--acOn` (accentOn) | `#FFFFFF` | `#08182C` | text/icon on `accentFill` |
| `--acTxt` (accentText) | `#0F5FD6` | `#7DB8FF` | tinted icon/text on `accentSoft` |
| `--acSoft` (accentSoft) | `#E8F0FE` | `#16263D` | tinted icon backgrounds |
| `--ok` (success) | `#16733A` | `#5BD08A` | low-risk badge foreground |
| `--okBg` (successBackground) | `#E4F3E9` | `#123324` | low-risk badge background |
| `--warn` (warning) | `#8A5300` | `#F2B04A` | medium-risk badge foreground |
| `--warnBg` (warningBackground) | `#FBEFDC` | `#3A2A10` | medium-risk badge background |
| `--dan` (danger) | `#B02419` | `#FF7B6E` | high-risk badge / destructive |
| `--danBg` (dangerBackground) | `#FBE9E7` | `#3B1C18` | high-risk badge background |
| `--ctl` (control) | `#FFFFFF` | `#3A3A3E` | secondary/destructive button fill |
| `--ctlBd` (controlBorder) | `rgba(0,0,0,.14)` | `rgba(255,255,255,.16)` | not a solid hex |
| `--ctl2` (controlSecondary) | `#F2F2F4` | `#2E2E32` | disabled button fill |
| `--neu` (neutral) | `#EFEFF2` | `#303034` | unselected ring segment, neutral icon tile |

Not in the 22-token set, only in the light-only `sys` demo block (no live
screen shows it, and no dark value is declared anywhere in the spec):

| Token | Light | Dark (approximated) |
|---|---|---|
| disabled button text | `#A0A0A6` | not specified — foundation plan approximates as `textTertiary` dark (`#98989E`) |

## Typography scale

SF Pro Text/Display, system stack, always `tabular-nums` for numbers.

| Name | Size / weight | Used for |
|---|---|---|
| Hero | 34 / 700 | Screen headline ("Limpe com confiança") |
| Metric | 42 / 700, tabular-nums | Big GB numbers |
| Title | 17 / 650 | Card/section titles |
| Body | 13 / 400 | Body copy |
| Caption | 11 / 500 | Captions, badge text |

SwiftUI's `Font.Weight` only exposes stops at 400/500/600/700 near this
range, so 650 renders as `.semibold` (600).

## Spacing / radius

- Spacing scale: 4 · 8 · 12 · 16 · 20 · 24 · 32
- Card corner radius: 12 (already `Layout.cardRadius` in the existing app)
- Control corner radius: 8
- Badge corner radius: 6
- Cards: 1px separator border + grouped background, no shadow
- Primary button padding is 18pt horizontal — a one-off, not on the spacing
  scale (secondary/destructive buttons use 16pt, which is on the scale)

## Screens in the spec

| ID | Description | Size |
|---|---|---|
| `1a` | Overview — with results · light | 1440×900 |
| `1b` | Overview — with results · dark | 1440×900 |
| `1c` | Caches — selection in progress · light | 1440×900 |
| `1d` | Caches — nothing selected · dark · EN | 1100×720 |
| `1e` | History · light | 1440×900 |
| `1f` | History — nothing logged yet · dark | 1100×720 |
| `1g` | Settings · light | 1440×900 |
| `1h` | Settings · dark | 1100×720 |
| `1i` | Overview — never scanned · light | 1100×720 |
| `1j` | Overview — scanning · dark | 1100×720 |
| `1k` | Caches — filters hide everything · light | 1100×720 |
| `1l` | Caches — scan can't start · dark | 1100×720 |
| `1m` | Durable registry failure — informs, doesn't act · light | 1100×720 |

Full markup for each screen: grep `MacDevClean Redesign.dc.html` for
`<div id="1x"` (each screen is a self-contained frame with inline styles;
`id`s are also referenced in future per-screen plans and PR/commit messages).
