# Pulp Style Guide

The visual design system for the Pulp Markdown editor. Every rendered element draws
from these tokens — no inline colors, no magic numbers. This keeps the editor
coherent and makes theming (light/dark, custom accent) a single source of truth.

## Principles

1. **Content first.** Chrome defers to text. Borders are hairlines, backgrounds are
   barely-there fills, markers shrink away when not being edited.
2. **Semantic, adaptive color.** Every color resolves correctly in light and dark
   mode via system semantic colors. No hard-coded RGB.
3. **Cross-platform parity.** Colors are defined once in `PulpPalette` and resolve to
   the right `NSColor` / `UIColor` per platform.
4. **One scale.** Typography and spacing follow a single rhythm so headings, body,
   code, and tables feel like one document.

## Color Tokens

### Text

| Token | Light/Dark source | Used for |
|-------|-------------------|----------|
| `textColor` | label | Primary body text, headings, cell content |
| `secondaryTextColor` | secondaryLabel | Markers (revealed), blockquotes, captions, dimmed |
| `tertiaryTextColor` | tertiaryLabel | Separator-row text, very low emphasis |

### Backgrounds (fills, not label colors)

| Token | Source | Used for |
|-------|--------|----------|
| `backgroundColor` | textBackground / systemBackground | Editor canvas |
| `codeBackgroundColor` | subtle fill (~6% label) | Code block + inline code background |
| `tableHeaderBackground` | subtle fill (~8% label) | Table header row |
| `tableRowStripeBackground` | faint fill (~4% label) | Alternating table data rows |

### Lines

| Token | Source | Used for |
|-------|--------|----------|
| `borderColor` | separator (~12% label) | Table outer border, column/row dividers |
| `strongBorderColor` | separator (~25% label) | Header bottom border, horizontal rules |

### Accent

| Token | Source | Used for |
|-------|--------|----------|
| `accentColor` | controlAccent / tint | Links, list bullets, ordered numbers |
| `checkboxTintColor` | accent | Checked checkbox fill |
| `highlightColor` | systemYellow @ 30% | `==highlight==` background |

## Typography

System font (San Francisco) throughout. Sizes in points, scale with Dynamic Type
on iOS.

| Element | Size | Weight |
|---------|------|--------|
| H1 | 28 | bold |
| H2 | 24 | bold |
| H3 | 20 | bold |
| H4 | 18 | semibold |
| H5 | 16 | semibold |
| H6 | 14 | semibold |
| Body | 16 | regular |
| Code | 16 | Menlo regular |
| Table cell | 14.4 (0.9× body) | regular |
| Table header | 14.4 | semibold |
| Caption / marker (revealed) | ~13.6 (0.85× body) | regular |

## Spacing

| Context | Value |
|---------|-------|
| Editor inset | 40pt horizontal, 20pt vertical |
| Paragraph spacing | 0.5× body |
| Heading spacing before | 0.8× body |
| List indent | 28pt |
| Table cell padding | 10pt horizontal |
| Code block padding | 8pt |
| Corner radius (code, tables) | 4–8pt |

## Tables (applying the system)

- **Outer border:** `borderColor`, 1pt, 4pt corner radius
- **Header:** `tableHeaderBackground` fill, semibold text, `strongBorderColor` 1.5pt bottom border
- **Data rows:** alternating `tableRowStripeBackground` on odd rows, `borderColor` 0.5pt dividers
- **Columns:** content-proportional widths, `borderColor` 0.5pt vertical dividers
- **Cell text:** `textColor`, 14.4pt, 10pt horizontal padding
