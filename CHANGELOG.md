# Changelog

## Unreleased

- Optional consumer capabilities: hosted SwiftUI cells and headers, full-width supplementary rows with variable or measured heights, selection modes and disabled rows, caller-owned sorting and row refresh, focus and click callbacks, new-tab activation, column reordering, scroll-end notification and native drag/drop hooks. Existing table styling and defaults remain intact.
- Hosted content is restricted to visible cells, inherits the embedding SwiftUI environment, and measures natural cell/detail height.
- Native accessibility exposes bounded rows/cells, hosted controls, sort headers, selection and activation. Optional header height/commands and interaction gates preserve richer host workflows.

## 0.1.2 (2026-10-29)

- Badge cells: `FlyCellValue.badge` and `.badges`, `FlyBadge` (text, `FlyTint`, `FlyBadgeFill` tinted/solid/quiet, optional SF Symbol), `FlyTint` with FlyUI's six tones and eight category hues (swatch and solid values from FlyUI). Column initializers `FlyColumn(_:badge:fill:symbol:tint:)` and `FlyColumn(_:badges:fill:tint:)`.
- Renderer draws pills natively from the cell cache: FlyUI capsule geometry (8pt padding, caption text, 1pt edge on tinted), light and dark washes, a "+N" tail when pills overflow the cell.
- Gallery: Status as a tinted badge, a Practice column of quiet category tags.

## 0.1.1 (2026-10-29)

- `FlyTableTheme.flyUI`: FlyUI's default table look from its semantic tokens (light and dark): raised header strip with the sorted heading tinted, surface/raised row stripes, border-default hairlines, baltic selection tint with the focus-border edge, 14pt body-compact cells and label-strong headings. `.theme(_:)` on `FlyTable`.
- `FlyTableStyle.card`: FlyUI's card-family surface, a rounded bordered container with full-width rows.
- Renderer: `headerSortedBackground` and `selectionEdge` theme slots; columns re-flow when the clip view's frame changes (window resize), not only its bounds.
- Gallery: FlyUI theme toggle, card style default, surface-coloured window background.

## 0.1.0 (2026-10-29)

First public cut.

- `FlyTableCore`: `FlyColumnSpec` with fixed, flex and fit widths; `FlyColumnLayoutState`
  (order, widths, hidden; Codable) and `FlyColumnLayoutResolver`; `FlyRowGeometry` (uniform and
  prefix-sum variable heights); `FlySortOrder` with click/shift-click semantics and `FlySorter`
  index permutations; `FlySelection` with anchor, focus, extension and keyboard travel;
  `FlyCellValue` with shared formatters and typed comparison; `FlyCellCache`.
- `FlyTable` (macOS): custom-drawn `NSView` renderer in an `NSScrollView` with cached Core Text
  lines, floating header, pinned leading columns, inset/fullWidth/plain styles, three densities,
  alternating rows, row and column separators, hover, emphasized and unemphasized selection, sort
  by header click, resize by divider drag, show/hide/reset columns from the header menu, full
  keyboard selection, right-click-selects-then-menu, double-click/Return activation; `FlyColumn`
  with key-path initializers and a result builder; `FlyTableTheme`.
- `FlyTableGallery`: synthetic data at 1k, 100k and 1M rows.
- Docs: proposal, four research reports, ADR-0001.
