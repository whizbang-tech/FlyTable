# Data-table design and interaction art: what a best-in-class native Swift table should match or beat

Research date 2026-10-29. Verification: [fetched] = page/source read directly; [tree] = GitHub file tree read; [search] = secondary sources only.

## 1. Catalogue

### A. Swift / Apple-platform design systems and apps

| Project | Status | How the table/list is built | Notes |
|---|---|---|---|
| Microsoft Fluent UI Apple — github.com/microsoft/fluentui-apple | Open, active | iOS: `TableViewCell`, `TableViewCellShimmer`, `TableViewCellFileAccessoryView` (cell-level only). macOS has no table/grid [fetched]. | Cell anatomy reference (leading icon, title/subtitle/footer, accessory, shimmer skeleton). Not a data grid. |
| IBM Carbon | No Swift [search]. | — | Use Carbon's web DataTable spec as a feature bar. |
| Shopify Polaris | No native Swift [search]. | — | Web DataTable guidance (numeric alignment, totals row). |
| Airbnb Epoxy — github.com/airbnb/epoxy-ios | Open | `EpoxyCollectionView` drives `UICollectionView` declaratively: `ItemModel`s with `dataID`, `setItems(_, animated:)` diffs and animates [fetched]. | Model for a result-builder DSL over a native container. |
| Square Listable (+ Blueprint) — github.com/square/Listable | Open, ships in Square POS | `UICollectionView` with a custom layout; `Section`/`Item` with `swipeActions`, `reordering`; views created only for what is on screen [fetched]. | Per-item callbacks, animated diffing, appearance/behaviour split. |
| Telegram-iOS — `submodules/Display/Source/ListView.swift` | Open | Fully custom engine: hidden `ListViewScroller` whose pan gesture is re-routed; items are `ListViewItem` → `ListViewItemNode` with no reuse pool; updates through `ListViewTransactionQueue`, `dispatchOnVSync`, `CADisplayLink` [fetched]. | Async layout off-main, transaction batching, vsync-aligned commits. |
| Signal-iOS — Chat List | Open | `CLVTableDataSource` over `UITableView`, with explicit `CLVRenderState`/`CLVViewState` and a `CLVLoader` [fetched]. | Immutable render state separate from view state; filters first-class. |
| NetNewsWire | Open (MIT) | Mac: `TimelineTableView.swift`, `TimelineTableRowView.swift`, `TimelineLayout.swift` (AppKit `NSTableView` with custom row views) [tree]; sidebar `NSOutlineView`. iOS: `UITableViewDiffableDataSource` migrating to `UICollectionViewDiffableDataSource` [fetched]. | The canonical "do it the AppKit way" app. |
| Sequel Ace — `Source/Views/TableViews/` | Open | `SPTableView` → `SPCopyTable`: copy as tab/CSV/SQL INSERT, drag-out rows as TSV, `isNullAtRow:column:` distinguishes NULL from "NULL", `shouldUseFieldEditorForRow:` chooses in-cell vs sheet editor, `autodetectColumnWidths` runs off-main; `SATableHeaderView`, `SAFieldEditorCommitPolicy` [fetched]. | Best open database grid on NSTableView. |
| Pulse (kean) — kean.blog/post/pulse-pro | Open (MIT) | PulseUI console is SwiftUI `List(selection:)`. Pulse Pro (Mac) chose `NSTableView` over SwiftUI `Table` for user-configurable columns and efficient refresh; user-addable/hideable/sortable columns remembered; click row number to pin, pins drawn in the scroller [fetched]. | Confirms the AppKit-vs-SwiftUI-Table tradeoff. |
| Kickstarter ios-oss | Open | `ValueCellDataSource` serves both `UITableView` and `UICollectionView` [tree]. | One data source over both containers. |
| Mastodon iOS, Ice Cubes, Wikipedia iOS, Firefox iOS, WordPress iOS, DuckDuckGo iOS, Pocket Casts | Open | UIKit `UITableView`/`UICollectionView` or SwiftUI `List` [tree]. | Wikipedia's `ColumnarCollectionViewLayout` is a reference for adaptive column counts. |
| Closed: TablePlus, Postico, Proxyman, Paw, Craft, Things 3 | Closed | — | Admired: very quick inline editing of query results (TablePlus); Swift-native macOS-first UX with inline row editing (Postico); safe mode guarding edits (TablePlus); remember row selection at launch (Proxyman 5.22); keyboard shortcuts "second to none" (Things 3). |

### B. Platform-agnostic references

| Reference | Key takeaways |
|---|---|
| TanStack Table v9 — tanstack.com/table | Headless plugin core. Stock features: cell selection, cell spanning, column faceting/filtering/grouping/ordering/pinning/resizing/sizing/visibility, global filtering, row aggregation/expanding/pagination/pinning/selection/sorting. Virtualization is a separate library. Features contribute their own state, options, lifecycle hooks and APIs; omitted features vanish from the types. |
| Glide Data Grid — github.com/glideapps/glide-data-grid | Canvas-rendered; "scales to millions of rows"; cells produced lazily via `getCellContent`; native scrolling. Cell kinds (Text, Number, Uri, Image, Bubble, Boolean, Markdown, Drilldown, Protected, Custom), `rangeSelect/columnSelect/rowSelect`, `rowMarkers`, selection blending (`exclusive/mixed/additive`), `freezeColumns`, group headers, `fillHandle` + `allowedFillDirections`, `onPaste`/`coercePasteValue`, `trailingRowOptions`, `drawCell`/`drawHeader` overrides, built-in `showSearch`, `highlightRegions`, per-row `rowHeight` function, `updateCells` partial redraw. |
| AG Grid | Community: filtering, sorting, cell editing, CSV, drag & drop, selection, a11y, infinite scroll, pagination, server-side data. Enterprise: range selection, row grouping + aggregation, pivoting, Excel/PDF export, clipboard, master/detail, tree data, column menu, context menu, tool panels, find, formulas, charts. |
| MUI X DataGrid | Community: editing, sorting, filtering, pagination, column groups. Pro: column pinning, column/row reorder, tree data, advanced filtering, virtualization. Premium: row grouping + aggregation, row pinning for aggregation footers, Excel export and paste. |
| Retool Table | Constant performance from 100 to 100,000 rows; custom virtualizer; auto-detected column types; primary key keeps selection/changes stable across filter/sort/pagination; editable columns write back; column aggregation. |
| Linear | Display options: grouping, sub-grouping, ordering with reverse, display properties that change what each row shows without hiding rows. Selection: arrows or J/K focus, X selects, Shift+arrows extend, Shift-click/Cmd-click, Cmd+A selects all in view, Esc clears; then Cmd+K or right-click acts. Headers hold filters + display options. No shipped density toggle found. |
| Notion databases | Freeze up to a column, property visibility per view, group + sub-group, sort, nested AND/OR filters, side peek/center peek/full page. |
| Airtable grid | Primary field can't be hidden; drag headers to reorder; four row heights; Space expands record, Shift+Space expands one cell; fill handle infers series from two cells. |
| Attio | Client-side updates without blocking on round trips; app should feel native with local storage; lists virtualized by default. |
| Vercel Geist Table | `striped`, `bordered`, `interactive`, `virtualize` variants; sortable headers are buttons with decorative arrow and SR-announced next state; `—` for unknown values, never N/A/null; `tabular-nums` for numeric columns; empty state rendered outside the table. |
| shadcn DataTable | A guide, not a component: combining all variations into one component loses headless flexibility. |
| GitHub Primer DataTable | Left-align default; right-align numbers; densities Condensed/Normal/Spacious; sortable tables must have a default sort; first click ascending; row actions in last column with visually hidden header; group >1 action in a menu, pull out at most one; `rowHeader` on the identifier column. |
| Atlassian Dynamic Table | Never rely on highlighted rows to convey meaning, selection or focus; never put controls in headings; unique per-row action labels; after delete, focus moves to the next focusable item. |
| IBM Carbon DataTable | Row heights xs 24 / sm 32 / md 40 / lg 48 / xl 64; header matches row size; toolbar ≤5 actions; batch action bar replaces toolbar on selection and disables row-level actions; tri-state header checkbox; 3-state sort (unsorted hint on hover only, indicator only on the sorted column); zebra modifier; overflow menu persistent by default but always visible on touch; <3 actions inline; skeleton over spinner; long titles wrap to 2 lines then truncate with tooltip. |
| Material (M2) data tables | 52dp rows / 56dp header, text left / numbers right, checkbox leading column, hover/selected states, sort arrow on hover. M3 has no data-table spec. |
| Apple HIG, Lists and tables | Click heading to sort, click again to reverse; let people resize columns; consider alternating row colors in a multicolumn table; outline view for hierarchy; middle-ellipsis; Title Case noun-phrase headings. |
| Apple HIG, Outline views | Hierarchy in first column only; Option-click disclosure expands all descendants; retain expansion choices; sorting applies at each hierarchy level; single-click to edit, double-click to open. |
| Finder | Click column name to sort, click again to reverse; Control-click any heading to toggle columns; sort persists per folder. Double-click a divider right-sizes that column; Option-double-click right-sizes all; Tahoe 26.1 adds "Resize Columns To Fit File Names". |
| Numbers | Single-click selects cell, double-click edits; drag the white dot to extend a range; Cmd-click for non-adjacent; yellow autofill handle appears on hovering the selection border; series inferred from two cells. |
| Nielsen Norman, Data Tables | Tasks: find, compare, view/edit/add one row, act on records. First column = human-readable identifier; sticky header row and header column; hide/reorder columns via a menu because header drag-drop has low discoverability and poor accessibility; show a hidden-column indicator; edit-in-place only for narrow tables, prefer a non-modal panel; inline buttons for ≤2 actions; batch via checkboxes + action bar. |
| Smashing Magazine, table design patterns / complex tables | Column toggle with dropdown to restore; scroll shadows for horizontal overflow; headers stay in the a11y tree when hidden; build cell types atomically with all states defined; min widths per content type; rounded numbers with full precision when active; filter boxes get a reset; pinned key columns; inline edit needs validation and auto-formatting; batch toolbar enablement depends on selection. |

## 2. Consolidated feature bar

Data model: headless core separated from rendering; stable row identity so selection, edits and scroll survive sort/filter/paginate; typed cell kinds with per-type states; lazy cell content provider and incremental updates; immutable render state separate from view state; async transaction queue committed on vsync; real NULL vs the string "NULL"; `—` for unknown; client-first updates.

Columns: resize by divider drag with min/max; double-click divider right-sizes, Option-double-click right-sizes all; content-aware autosize off-main; reorder by drag and via a menu; show/hide with a hidden-column indicator; Control-click header for column toggles; pin leading and trailing; primary identifier column cannot be hidden; column groups and spanning cells; width policies grow / growCollapse / auto / fixed; min widths per content type; persisted layout.

Rows: at least three densities; header height matches row size; variable heights and wrap-vs-truncate per column; outline disclosure in first column only, Option-click expands all, retained expansion state; grouping and sub-grouping with collapsible groups; aggregation footers via pinned rows; row pinning; trailing append row; row reorder by drag; expandable detail rows and master/detail; hover highlight on mouse only; row actions revealed on hover but always visible on touch.

Cells: left-align text, right-align numbers with tabular numerals; header alignment follows column; middle ellipsis for identifiers; tooltips for truncated headers; rounded display with full precision on edit; custom draw hook with the default drawer callable.

Selection and keyboard: row, cell, column and range selection with explicit blending; rowMarkers column; arrows/J-K move focus, X toggles, Shift+arrows extend, Cmd-click non-contiguous, Cmd-A selects the filtered set, Esc clears; Option-arrow/Home/End; Space to peek, Shift+Space to expand a cell; tri-state header checkbox; batch action bar replaces the toolbar; click row number to pin with marks in the scroller; remember and restore selection.

Editing: single-click edits and double-click opens where both make sense; Enter/Tab commit and move; explicit commit policy object; in-cell editor for simple values, sheet or panel for complex; validation with coercion, auto-formatting, per-row errors; fill handle with series inference; copy/paste in TSV, CSV and domain formats; safe mode / explicit write-back of a change set.

Sorting, filtering, grouping: click heading to sort, click again to reverse; only the sorted column shows an indicator; unsorted hint on hover; a sortable table has a default sort; sort per hierarchy level; multi-column sort; manual ordering as a sort mode; per-column filters with reset, global/fuzzy search, faceted values, nested AND/OR, active-filter indicator; group + sub-group with aggregation.

Virtualization and performance: materialize only visible rows and columns; constant-time scrolling at 100k+ rows; native scroll physics; off-main layout, batched transactions, vsync commits; cache per-row formatted strings; diffable updates that leave unchanged rows untouched; skeleton rows over spinners.

Styling: flat theme object mapped to tokens; alternating rows opt-in for wide tables; bordered/striped/interactive variants; scroll shadows for horizontal overflow; headers hold filters and display options.

Accessibility: sortable headers announce the next state; table labelled by title; identifier column marked as row header; unique per-row action labels; focus moves to the next item after delete; hidden action-column header kept for screen readers; hidden columns discoverable via menu.

State persistence: per-view column order/width/visibility/frozen, sort, filters, grouping, density, display properties; per-user vs shared default; expansion, selection, scroll position restored on relaunch.

## 3. Specific details worth copying (with source)
1. Finder's header interactions (Apple Mac Help mchlp1745; TidBITS 2026-01-29).
2. HIG middle-ellipsis truncation (HIG Lists and tables / Outline views).
3. Option-click disclosure expands the whole subtree; expansion state retained (HIG Outline views).
4. Numbers' selection model and autofill handle (Apple Numbers guide).
5. Linear's selection grammar and display properties (linear.app/docs).
6. Carbon's 3-state sort and batch action bar; header height equals row height.
7. Primer's row-actions rule.
8. Nielsen Norman: menu for hiding/reordering columns, freeze the identifier column, non-modal panel for editing.
9. Glide's selection blending, fill handle API, lazy `getCellContent`, `updateCells`.
10. TanStack's plugin core.
11. Pulse Pro: user-configurable persisted columns, row-number pins drawn in the scroller.
12. Sequel Ace: off-main autosize, NULL vs "NULL", copy as TSV/CSV/SQL, in-cell vs sheet editor, commit policy.
13. Telegram's ListView transaction queue on vsync.
14. Listable/Epoxy: declarative items with `dataID`, per-item behaviours, animated diff.
15. Geist content rules.
16. Airtable: Space to expand the record, four row heights, primary field never hideable.
17. Retool: primary key makes selection and edits survive filter/sort/pagination.
18. Proxyman: remember row selection and reselect at launch.

## 4. Anti-patterns to avoid
Header drag-and-drop as the only way to reorder/hide columns; controls inside column headings; relying on row highlight colour to convey meaning; zebra striping on short/narrow tables; centered text columns and left-aligned numbers; modal dialogs for row editing; edit-in-place on wide tables; hover-only row actions on touch; spinners where skeletons are expected; expand-all on deferred-loading rows; `N/A`/`null`/empty for unknown values; monolithic "one component does everything" APIs; shipping a table without user-configurable persisted columns; cell reuse that leaves blank cells during fast scroll; sorting that reorders hierarchy across levels.

Gaps: Material M2/M3 pages could not be fetched; several apps verified by file-tree listing only; Linear has no documented density toggle.
