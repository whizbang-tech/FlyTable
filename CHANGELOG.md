# Changelog

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
