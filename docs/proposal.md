# FlyTable: research and proposal

Date: 2026-10-29. Author: Claude (Fable 5.1) for Andrew Dreis. Status: proposal, awaiting Andrew's
decisions in §8 before the `whizbang-tech/FlyTable` repository is created.

Scope of the research: open-source Swift tables on GitHub and package indexes, Apple's first-party
table APIs (SwiftUI `Table`/`List`, AppKit `NSTableView`, UIKit `UICollectionView`), Swift design
systems and open-source Mac/iOS apps with notable tables, platform-agnostic data-grid references
(TanStack, Glide, AG Grid, Linear, Notion, Finder, Numbers, HIG), and the engineering literature
on virtualization and rendering at 100k–1M rows. Four parallel research sweeps ran on 2026-10-29;
every repository statistic was read from the GitHub API that day and every Apple availability
figure from the doc page. Forum reports are labelled as anecdotes where they are.

---

## 1. Summary

There is no mature, maintained, macOS-first, open-source Swift table to adopt. Every public
candidate is a UIKit grid, a thin SwiftUI layout helper, a small experiment, or source-available
under a non-commercial licence. Apple's own `Table` is `NSTableView`-backed on macOS but has
locked row heights, no readable or persisted column widths, no header styling, no frozen columns,
no floating group rows, and documented hangs at 1k–5k rows on selection and update. The field's
best practitioners (Pulse, NetNewsWire, Sequel Ace, the authors in Michael Tsai's roundups) all
end at the same place: a native scroll view with a custom-drawn or cell-recycled body, under a
SwiftUI API.

The proposal is therefore to build FlyTable as a **headless core plus a custom-drawn native
renderer**, with a SwiftUI API that reads like Apple's `Table` where Apple's is right and goes
further where it is not. The core (columns, width policy, sort, filter, group, selection, viewport
maths, cell cache) is pure Swift and fully testable. The primary renderer is one viewport-sized
`NSView`/`UIView` inside a native scroll view, drawing only visible rows × visible columns from
cached Core Text lines, with the frozen header and pinned columns drawn in the same pass. A
secondary pooled-row SwiftUI renderer serves rich interactive cells on modest data. This is the
only architecture in the research that reaches 1M rows at display refresh rate while keeping
native scroll physics, selection, keyboard and accessibility semantics.

Visually, FlyTable targets Finder/Mail density and restraint, not the chrome of the current
FlyUI table: 24–28pt rows at comfortable density, a single quiet header, columns that fill, no
utility columns unless asked for, hairline or alternating rows as options, and selection drawn
the way AppKit draws it (accent when emphasized, grey when the window is inactive).

---

## 2. What FlyUI has today

Read from `Platform/FlyUI` (branch `Dreis/edits-10-27`) and the snapshot fixtures under
`Tests/FlyUISnapshotTests/Fixtures/datatable`.

Three engines coexist:

| Engine | Where | How it renders | Call sites |
|---|---|---|---|
| `FlyTable` | `DataDisplay/Table/FlyTable.swift`, 380 lines | `GeometryReader` → `ScrollView([.horizontal, .vertical])` → `LazyVStack(pinnedViews:)` → one SwiftUI view per cell | 27 in Amicus/Apps |
| `FlyDataTable` | `DataDisplay/Table/FlyDataTable.swift`, 1,689 lines | Same engine plus toolbar, filters, grouping, detail rows, inline edit, resize handles, pagination, export, load states; 19 style kinds, 47 tokens | 10 |
| Native engine | `Carried/DataDisplay/FlyNativeDataTable.swift` + `FlyNativeTableViews.swift`, ~1,400 lines, macOS only, "carried, do not edit" | `NSTableView` subclass, `reloadData()` on every `rowsRevision` change, `NSTextField` for value columns, `NSHostingView` per visible custom cell with the whole `EnvironmentValues` copied in | reached via `FlyDataTable(rows:rowsRevision:…)` |

Structural problems:

- The two SwiftUI engines create views lazily but never recycle them; every visible cell is a live
  SwiftUI view whose content is `AnyView`-erased in `FlyTableColumn.content`, which defeats
  structural identity and diffing. Memory grows with scroll distance. There is no column
  virtualization.
- The native engine reloads everything on any change, has no diffable or batched updates, and pays
  an `NSHostingView` plus environment copy per custom cell.
- Column width is a per-column constant (minimum 120, maximum 480) rather than a layout policy.
  There is no fill, flex, or fit-to-content, so columns do not fill the surface (visible gap on the
  right in the `standard` snapshot).
- Pinned header and pinned column are modifiers on the SwiftUI engine; nothing scrolls in sync at
  native speed.
- Row geometry (height, chrome widths) is computed inside the component (`Metrics`), outside the
  style, so a style cannot make the table denser.

Visual problems, from the snapshots: ~37pt rows and header at comfortable density; an oversized
toolbar (search field plus five pill buttons); the sorted column's header drawn as a tinted block;
a checkbox column, a disclosure column and a trailing circular "more" button on every row by
default; full-width hairline dividers between every row plus vertical rules in some variants; and
columns that stop short of the trailing edge.

---

## 3. Best-known art, ranked

### 3.1 Open-source Swift (GitHub, verified 2026-10-29)

| Rank | Project | Stars / last push / licence | What to take |
|---|---|---|---|
| 1 | NGTable (ngtable/NGTable) | 1 / 2026-10 / PolyForm Noncommercial + paid | Metal glyph-atlas text rendering; in-table sort, filter and summary pipeline; selection keyed to record identity across reloads; frozen leading and trailing columns; column groups; saved layouts. Claims 120fps at 20k rows with 45k changes/s. Study only; licence forbids business use. |
| 2 | kean "Not List" + flocked/AdvancedCollectionTableView | Pulse 7.2k / 2026-10 / MIT; ACTV 55 / 2026-09 / MIT | The canonical `NSViewRepresentable` → `NSScrollView` → `NSTableView` bridge; `CellRegistration`, `NSHostingConfiguration`, diffable snapshots, Quick Look and Backspace conventions. Kean dropped SwiftUI cells for AppKit ones at 150k rows. |
| 3 | bannzai/SpreadsheetView | 3.5k / 2024-05 / MIT, iOS only | Separate `LayoutEngine`, `ReuseQueue`, binary-searched row/column offsets, frozen panes and merged cells as first-class layout concepts. Port the design, not the code. |
| 4 | christopher-inegbedion/DataGrid | 0 / 2026-10 / MIT | Pure SwiftUI two-axis pinning via `visualEffect`, visible range via `onScrollGeometryChange`, SwiftUI-free `GridGeometry` with prefix sums over row heights. The template for a SwiftUI-native virtualized body. |
| 5 | Nil Coalescing "Custom lazy list" (article, 2025-03) | — | Row recycling in SwiftUI: custom `Layout`, identity = index mod pool size, `@State` reset on data-ID change. |
| 6 | pavankataria/SwiftDataTables | 461 / 2026-02 / MIT, iOS | Key-path column declaration, diff-then-apply updates, left/right frozen columns, claimed 50k rows in 0.25s. |
| 7 | nlampi/SwiftGridView | 67 / 2026-09 / MIT, iOS | Grouped (spanning) headers, per-axis pinch zoom, Swift 6 `@MainActor` data source. |
| 8 | openalloc/SwiftTabler | 145 / 2023-05 / Apache-2.0 | Three substrates (List, LazyVStack, LazyVGrid) behind one column DSL; a map of SwiftUI's limits. Dormant. |
| 9 | IGListKit, DifferenceKit, Epoxy, Texture, Listable | 13k / 3.7k / 1.3k / 8.2k / active | Section-controller decomposition, O(n) Heckel diff (DifferenceKit: 0.035s at 100k vs 5.03s for `CollectionDifference`), `dataID` identity, off-main measurement, appearance/behaviour split. |
| 10 | baudehlo/SimpleSpread + Sequel-Ace | 14 / 2026-10 / MIT; 7.6k / 2026-10 / MIT | Excel-grade keyboard state machine (Ready/Enter/Edit, F2, Cmd+arrow, fill handle, per-gesture undo); real NSTableView grid subclasses (`SPCopyTable`, field-editor commit policy, NULL vs "NULL", off-main column autosize). |

Also catalogued and set aside: exyte/Grid (2.1k; CSS-grid track vocabulary `fr`/`pt`/`fit` is
worth borrowing for width policy), SwiftUIX (8.2k; no table), QGrid/GridStack/swiftui-grid
(abandoned), darrarski/swiftui-simple-table (22; sticky-header modifier only), ChimeHQ/Outline
(25; clean SwiftUI-over-`NSOutlineView` bindings), FastList (NSTableView-backed `List`),
HexFiend (windowed data sources), Telegram-iOS `ListView` (vsync transaction queue), Signal
(immutable render state), NetNewsWire (AppKit done right). No open-source Metal or Canvas-rendered
Swift grid exists besides NGTable.

### 3.2 Apple first-party

- **SwiftUI `Table`** (macOS 12+/iOS 16+): `NSTableView`-backed on macOS, `UICollectionView` on
  iOS. Has sort-order bindings, selection, `TableColumnCustomization` (order and visibility only,
  macOS 14+), `DisclosureTableRow`, `contextMenu(forSelectionType:)`, `TableColumnAlignment`
  (`.numeric`), `alternatingRowBackgrounds`. Verified gaps: locked row height on macOS; column
  widths cannot be read, set or persisted (Apple DTS, Feb 2025: "not supported"); no header styling
  beyond hiding; no grid-line or divider control; no frozen columns; no horizontal scroll on iPad;
  sections do not float on macOS; ten-column builder cap; `if`/`AnyView` inside the rows `ForEach`
  forces every row to build (13s selection hang at 1,219 rows, forum 739849); macOS 15.5 and Tahoe
  regressions (FB21850924, FB21860141); no cell recycling. WWDC25 and WWDC26 added nothing to
  `Table`; WWDC25 improved macOS `List` at 100k items by 6×/16× through scheduling, not
  architecture.
- **AppKit `NSTableView`/`NSOutlineView`** remain the reference semantics: view-based cell reuse,
  `columnAutoresizingStyle`, `autosaveName`, `NSTableView.Style` (inset/fullWidth/sourceList/plain),
  `floatsGroupRows`, `NSTableRowView` selection drawing (emphasized vs unemphasized), batched
  `beginUpdates`, `NSTableViewDiffableDataSource` (macOS 11+), type-select, row actions, drag and
  drop. Known limits: no column virtualization (200 rows × 150 columns is unusable even here);
  auto-height rows grow but don't shrink; Tahoe header-scroll bug unless inset 1pt.
- **Hosting**: `NSHostingSizingOptions` (macOS 13) should be emptied for cell hosting views; Apple's
  own guidance is one hosting view per cell, updated by swapping the root view. `UIHostingConfiguration`
  (iOS 16) is the sanctioned way on iOS.
- **Relevant modern SwiftUI**: `Layout` protocol and `LayoutValueKey` (macOS 13), `onGeometryChange`
  (back-deployed to macOS 13), `onScrollGeometryChange` and `onScrollPhaseChange` (macOS 15/iOS 18),
  `visualEffect` and `scrollPosition` (macOS 14), `TextRenderer`/`Text.Layout` (macOS 14),
  `@Observable` per-row view models (WWDC25 pattern), Liquid Glass scroll-edge effects (macOS 26),
  `dragContainer`/`draggable(containerItemID:)` for multi-row drags (macOS 26).

### 3.3 Design and interaction references

Catalogued with sources in the research notes: Microsoft Fluent UI Apple (cell anatomy only; no
Mac table), Square Listable and Airbnb Epoxy (declarative items over native containers), Telegram
and Signal (bespoke engines), NetNewsWire, Sequel Ace and Pulse Pro (AppKit tables with
user-configurable persisted columns), Finder, Numbers, Mail and Xcode; TanStack Table v9,
Glide Data Grid, AG Grid, MUI DataGrid, Retool, Linear, Notion, Airtable, Attio, Vercel Geist,
shadcn, GitHub Primer, Atlassian, IBM Carbon, Apple HIG (Lists and tables, Outline views, Column
views), Nielsen Norman and Smashing Magazine.

Details worth copying, each with its source:

1. Finder: click a heading to sort, click again to reverse; Control-click a heading for the column
   toggle menu; double-click a divider to right-size, Option-double-click to right-size all; sort
   persists per folder.
2. HIG: middle-ellipsis truncation for identifiers; Option-click a disclosure to expand the whole
   subtree; retain expansion state; sort within each hierarchy level; alternating rows for wide
   multi-column tables only.
3. Numbers: single-click selects, double-click edits; drag the selection dot to extend; the
   autofill handle appears only on hovering the selection border; series inferred from two cells.
4. Linear: J/K or arrows move focus, X selects, Shift+arrows extend, Cmd-A selects the filtered
   set, Esc clears, then Cmd-K or right-click acts on the selection; "display properties" change
   what a row shows without hiding rows.
5. Carbon: three-state sort with the hint shown only on hover, indicator only on the sorted column;
   a batch action bar that replaces the toolbar while a selection exists; header height always
   equals row height; row heights 24/32/40/48/64.
6. Primer: row actions in the last column with a visually hidden header; group more than one action
   into a menu and pull out at most one; a sortable table has a default sort; first click ascends.
7. Nielsen Norman: a menu for hiding and reordering columns (header drag alone is undiscoverable
   and inaccessible); freeze the identifier column; prefer a non-modal panel to a modal for editing.
8. Glide Data Grid: lazy `getCellContent(row, column)` as the data contract; selection blending
   (exclusive, mixed, additive); `freezeColumns`; fill handle with allowed directions; `drawCell`
   override that can call the default drawer; per-row `rowHeight` function; `updateCells` partial
   invalidation.
9. TanStack: a headless core where each feature contributes its own state, options and API, and
   the type surface shrinks when a feature is omitted; virtualization lives outside the core.
10. Pulse Pro: user-addable, hideable, sortable, remembered columns; click a row number to pin;
    pins drawn as marks in the scroller.
11. Sequel Ace: content-aware column autosize off the main thread; NULL distinct from the string
    "NULL"; copy as TSV, CSV or SQL; in-cell versus sheet editor decided per cell; an explicit
    commit policy for field editing.
12. Geist: an em dash for unknown values, never N/A; tabular numerals in numeric columns; Title
    Case noun headers; the empty state rendered outside the table; sortable headers are buttons
    that announce the next state.

Anti-patterns to avoid: header drag as the only way to reorder or hide columns; controls inside
headings; row highlight colour carrying meaning; zebra striping on narrow tables; centred text or
left-aligned numbers; modal row editing; hover-only actions on touch; spinners where skeletons
belong; `N/A`/`null` for unknowns; a monolithic component that cannot be composed; sorting that
reorders hierarchy across levels; blank cells during fast scroll because layout is not cached.

---

## 4. What the research settles

1. **SwiftUI-only is not the path to the performance bar.** `List` and `Table` gather every
   identifier eagerly, diff on every update without an opt-out, and have no recycling. `LazyVStack`
   estimates content height, jumps under scrubbing, and keeps memory. Pooled-row SwiftUI
   (`onScrollGeometryChange` + custom `Layout`) works for ~60 rows of rich cells, with manual
   `@State` resets, and needs macOS 15.
2. **`NSTableView` is the right ceiling for ≤20 columns and the wrong one for wide grids.** It
   recycles rows but instantiates every visible column's cell view; 50 columns × 60 rows is 3,000
   live views before any hosting cost.
3. **The scalable answer is a custom-drawn document view.** One viewport-sized `NSView`/`UIView`
   in a native scroll view, drawing only visible rows × visible columns from cached `CTLine`s,
   layer-backed, `canDrawConcurrently`, frozen header and pinned columns drawn in the same pass.
   Cost is O(visible cells) regardless of data size. Glide proved the model on the web; NGTable
   proved it on the Mac. You then own selection, keyboard, focus, hover and the accessibility tree.
4. **Full-viewport redraw per frame must be assumed on macOS.** Responsive-scrolling overdraw is
   reported inactive since Sonoma. The draw budget is roughly 4ms for 3,000 cached line draws at
   50 × 60; profile on Intel and Apple silicon.
5. **120Hz on macOS is not something AppKit promises.** Validate with the Animation Hitches
   instrument on a ProMotion MacBook Pro; promise what is measured.
6. **Never measure a whole column.** 1M string widths take tens of seconds. Autosize by sampling
   visible rows plus a bounded random sample, clamped by min/max; use `CTLineGetTypographicBounds`.
7. **Diff to animate, not to render.** At 1M rows the renderer reads `(row, column)` on demand;
   diff only small changes for animated inserts/removes; otherwise invalidate the visible window.
8. **Per-row observation.** A one-cell change must invalidate one draw rect, not the table body
   (WWDC25's `@Observable` pitfall and fix).

---

## 5. Proposal: FlyTable

### 5.1 Architecture

Three layers, one package, no FlyUI dependency (the repository is public; FlyUI is private, so the
dependency runs FlyUI → FlyTable, never the reverse, exactly as FlyUI → FlySettings today).

**Layer 1, `FlyTableCore` (pure Swift, platform-free, 100% unit-testable).**
- `TableModel<Row>`: an index-addressed data source (array-backed by default, protocol for
  columnar or paged stores); `OrderedDictionary` keyed by `Row.ID` for stable identity.
- `Column` definitions: id, title, width policy (`.fixed`, `.flex(weight)`, `.fill`, `.fit`),
  min/max, alignment (`.leading`, `.trailing`, `.numeric`), pin (`.leading`, `.trailing`, none),
  cell kind (text, number, date, boolean, tag, link, image, custom), formatter, comparator,
  summary, editability.
- `ColumnLayout`: resolves widths against a viewport with NSTableView-style autoresizing
  semantics (uniform, sequential, lastColumnOnly) plus the grid-style `fr` distribution; persists
  order, width, visibility and pins keyed by column id.
- Sort, filter and group producing an index permutation, never copying rows; multi-key sort.
- `Selection`: rows, cells, columns and ranges with explicit blending; `IndexSet` plus id set so
  selection survives sort and filter.
- `Viewport`: offset and size → visible row range (fixed height, or a Fenwick tree over measured
  heights with estimates for unmeasured rows) and visible column range from prefix sums, with
  overscan.
- `CellCache`: `(rowIndex, columnID, dataVersion)` → shaped `CTLine` and width, bounded LRU.
- Invalidation API: `invalidate(rows:)`, `invalidate(cells:)`, `invalidateAll()`; animated
  insert/remove/move for small deltas.
- Keyboard state machine (Ready / Enter / Edit) and a commit policy object for editing.

**Layer 2, renderers behind one protocol.**
- `FlyTableNativeRenderer` (primary; macOS and iOS): custom document view in `NSScrollView` /
  `UIScrollView`, drawing visible cells from the cache; native selection look (accent when
  emphasized, `unemphasizedSelectedContentBackgroundColor` when the window is inactive); hover;
  focus ring; sort indicators; grid lines; frozen header and pinned columns in the same draw pass;
  right-click selects before the menu; type-select; Quick Look; drag and drop; a synthesized
  `NSAccessibility` table (rows, columns, cells, header relationships) for the visible window
  plus counts.
- `FlyTableHostedRenderer` (secondary): pooled SwiftUI rows via `onScrollGeometryChange` and a
  custom `Layout` for rich interactive cells on modest data (macOS 15/iOS 18+).
- `FlyTableReferenceRenderer` (test oracle, macOS): plain `NSTableView` with `NSTextField` cells,
  used by the test suite to check selection, keyboard and accessibility parity, never shipped as
  the default.

**Layer 3, `FlyTable` SwiftUI API.**
```swift
FlyTable(matters, selection: $selection, sortOrder: $sort, layout: $columnLayout) {
  FlyColumn("Matter", value: \.title).pinned().width(.flex(2))
  FlyColumn("Client", value: \.client)
  FlyColumn("Hours", value: \.hours, format: .number.precision(.fractionLength(2)))
    .alignment(.numeric).summary(.sum)
  FlyColumn("Status") { matter in StatusBadge(matter.status) }   // hosted cell
}
.tableStyle(.inset)                 // .inset, .fullWidth, .plain, .bordered
.rowHeight(.comfortable)            // .compact 24, .comfortable 28, .spacious 36, .fixed(pt), .measured
.alternatingRowBackgrounds(true)
.columnCustomization(.menu)         // Control-click header, column picker
.frozenHeader(true)
.editable(.onDoubleClick, commit: .onSelectionChange)
.contextMenu(forSelectionType: Matter.ID.self) { ids in … } primaryAction: { ids in … }
```
The API mirrors Apple's `Table` vocabulary (`sortOrder`, `selection`, `TableColumnCustomization`
semantics, `contextMenu(forSelectionType:)`) so adoption from a SwiftUI `Table` is mechanical,
and adds what Apple's cannot: row height, column width read/write/persist, header and divider
styling, pins, floating group rows, dynamic columns without the ten-column cap.

The table body chooses the renderer: native by default; hosted cells only for columns declared
with a view builder, and only for visible cells.

### 5.2 Visual direction

- Rows 24 / 28 / 36pt (compact / comfortable / spacious); header height equals row height.
- One header: 11pt semibold secondary label, sort chevron trailing in the sorted column only,
  hover hint for unsorted sortable columns, Control-click for the column menu, divider drag with
  double-click to fit.
- Columns fill the width by policy; numeric columns right-aligned with tabular digits; identifiers
  middle-truncated.
- Backgrounds: inset style with rounded selection (Big Sur and later), or full-width with
  alternating rows for wide grids; hairline separators optional, off by default in inset style.
- No utility columns unless declared: selection is the row highlight; a row-marker column
  (checkbox or number) is opt-in; a trailing actions column is opt-in with a visually hidden header.
- Batch action bar replaces the toolbar while a selection exists; the toolbar itself is the host's.
- Skeleton rows while loading; the empty state is rendered by the host, outside the table.
- Light, dark, increased contrast, inactive window, reduced motion; Liquid Glass scroll-edge
  behaviour under toolbars on macOS 26.
- FlyUI will supply its tokens through a `FlyTableTheme` struct (flat theme object, Glide-style);
  FlyTable ships a system theme that matches Finder and Mail.

### 5.3 Feature bar (v1 in bold, later unbolded)

Data: **index-addressed source, stable ids, typed cell kinds, lazy formatting, invalidation API**,
columnar store adapter, paged/remote store adapter.
Columns: **resize, reorder (drag and menu), show/hide, pin leading, width policies, fit-to-content
by sampling, persisted layout**, pin trailing, column groups, spanning cells.
Rows: **fixed and preset heights, alternating backgrounds, hover, floating group rows**,
measured variable heights, outline/disclosure rows, pinned top/bottom rows, trailing append row,
expandable detail rows, drag reorder.
Cells: **text, number, date, boolean, tag, link, hosted custom; tabular digits; middle ellipsis**,
image, markdown, drilldown, custom draw hook.
Selection and keyboard: **row single/multi/range, Cmd-A on the filtered set, Esc, arrows,
Option-arrow/Home/End, Shift-extend, type-select, right-click selects, double-click primary action,
Space Quick Look**, cell and column selection, J/K.
Editing: **double-click or Return to edit, Tab/Enter to move, explicit commit policy, in-cell text
editor**, fill handle, paste coercion, validation with per-row errors, copy as TSV/CSV.
Sort/filter/group: **click-to-sort with reverse, multi-key sort, in-memory filter, group with
counts**, faceted filters, nested AND/OR, aggregation footers.
Performance: **O(visible) drawing, cached lines, 1M-row scrolling, no memory growth, hitch budget
measured in CI**, off-main measurement, vsync-batched transactions.
Accessibility: **VoiceOver table semantics for visible cells with row/column headers, sort state
announcements, Full Keyboard Access**, custom rotors.
Persistence: **column layout, sort, density, expansion keyed per table id** via a `Codable`
state object the host stores.

### 5.4 Benchmarks and acceptance

Measured, not promised. The repo ships a `Benchmarks` target and a `Gallery` app.

| Scenario | Target |
|---|---|
| 1,000,000 rows × 50 columns, scrubbing the scroller | no blank cells, no memory growth after warm-up |
| 100,000 rows, wheel scroll at full refresh on ProMotion | hitch ratio ≤ 5ms/s (Animation Hitches instrument) |
| Select one row in 1,000,000 | < 16ms to redraw |
| Update 45,000 cells/s via `invalidate(cells:)` | sustained at ≥ 60fps |
| Sort 1,000,000 rows by one key | permutation only; UI stays responsive |
| Column resize drag | relayout under one frame |
| Memory, 1M rows × 50 columns of formatted text | bounded by the cell cache, not the data |

XCTest `measure` with `os_signpost` intervals around deceleration on macOS, and the SwiftUI
instrument's View Body lane for the hosted renderer. Snapshot tests for every style across light,
dark, increased contrast and inactive window, as FlyUI does today.

### 5.5 Milestones

1. **Core**: columns, width policy, sort, filter, group, selection, viewport maths, cell cache,
   with tests. Reference `NSTableView` renderer as the oracle.
2. **Native renderer on macOS**: drawing, scrolling, frozen header, pinned columns, selection,
   hover, keyboard, context menu, type-select, drag and drop, accessibility. Gallery app with
   1M synthetic rows. Benchmarks in CI.
3. **SwiftUI API and hosted cells**: `FlyTable`/`FlyColumn` builders, bindings, hosted custom
   cells through the pooled renderer, persistence. Optional visible-cell hosting, measured supplementary rows,
   caller-owned sorting, selection admission, native drag/drop and focus/scroll callbacks implemented on the
   consumer-capabilities branch (2026-10-29); integrated consumer visual acceptance remains pending.
4. **Editing**: in-cell editor, commit policy, Tab/Enter navigation, copy/paste.
5. **iOS/iPadOS**: `UIScrollView` document view, touch selection, horizontal scrolling on iPad,
   compact-width strategy (the host decides which columns survive, not a silent collapse).
6. **FlyUI adoption**: `FlyTableTheme` from FlyUI tokens; `FlyTable` and `FlyDataTable` become
   thin wrappers or are retired, consumer by consumer, starting with Amicus's matters and cases
   collections (37 call sites in total).

### 5.6 Risks

- Owning selection, keyboard, focus and VoiceOver semantics is the bulk of the work; the
  reference renderer and parity tests keep it honest.
- Full-viewport redraw per frame on macOS: keep per-frame draw under ~4ms at 50 × 60; fall back to
  per-row `CALayer` tiles if measurement says so.
- Variable row heights jiggle the scroller exactly as TextKit 2 does; fixed heights by default,
  measured heights opt-in with background measurement.
- The hosted renderer needs macOS 15/iOS 18 and manual `@State` resets.
- Apple is improving `List`/`Table` each release (6×/16× in macOS 26, DisclosureGroup fixes in 27);
  re-benchmark SwiftUI `Table` each June so the hosted path can swap to it when it clears the
  budget.
- Public repo: nothing from FlyUI, Amicus or client data may be referenced; synthetic data only.

---

## 6. Repository plan

- Name `whizbang-tech/FlyTable`, public, default branch `main`, Swift 6 language mode,
  `swift-tools-version: 6.0`, platforms macOS 15 and iOS 18 (the hosted renderer's floor; the
  native renderer could go lower later if a consumer needs it).
- Products: `FlyTableCore`, `FlyTable` (umbrella with renderers and SwiftUI API).
- Targets: `FlyTableCore`, `FlyTableNative`, `FlyTableHosted`, `FlyTable`, tests for each,
  `FlyTableBenchmarks`, and a `Gallery` example app with synthetic data generators.
- Files at the root following the sibling Fly repos: `README.md`, `AGENTS.md`, `CHANGELOG.md`,
  `CONTRIBUTING.md`, `Package.swift`, `LICENSE`, `docs/decisions/ADR-0001-architecture.md`
  (this proposal's §4–5 as the first decision record), `docs/research/` holding the four research
  reports.
- CI: GitHub Actions on macOS runners: build, tests, benchmarks with thresholds, snapshot tests.
- Dependencies: `apple/swift-collections` only. No FlyUI.
- Tracking: Foundry Board card (the board folder is not on this Mac; see §7).

---

## 7. Tracking note

The Foundry Board folder (`~/Documents/Kanban/Foundry Board`) does not exist on this Mac, so no
card was found or created. Pending card text: title "FlyTable: research proposal and new public
repository", column Planning, this file as the plan of record. It should be created on a machine
that has the board before implementation starts.

---

## 8. Decisions needed from Andrew

1. **Licence for the public repo.** MIT (simplest, matches Pulse, SpreadsheetView, Sequel Ace) or
   Apache-2.0 (patent grant, matches swift-collections and Epoxy). Recommendation: MIT.
2. **Platform floor.** macOS 15 + iOS 18 (recommended; unlocks `onScrollGeometryChange` for the
   hosted renderer) versus macOS 14 + iOS 17 (native renderer only at first).
3. **Name of the SwiftUI entry point.** `FlyTable` (recommended, matches the repo) collides with
   FlyUI's existing `FlyTable` until that one is retired; consumers would qualify with the module
   name during the transition, as FlyTree does today. Alternative: `FlyGrid`.
4. **Go-ahead to create the repository** under `whizbang-tech` as public with the layout in §6 and
   milestone 1 started.
