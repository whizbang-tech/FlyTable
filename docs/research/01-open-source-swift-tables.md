# Open-source Swift table / data-grid / spreadsheet survey (verified 2026-10-29)

Method: WebSearch across GitHub, Swift Package Index mirrors, CocoaPods and blogs, then verification of every repo's stars / last push / license via the GitHub REST API and README fetches. Star counts and push dates are from the API on 2026-10-29. Stars are rounded. Where a README did not state something, it says "not documented".

## Headline findings

1. There is no mature, maintained, macOS-first, open-source SwiftUI table that offers the full NSTableView feature set (resizable/reorderable columns, frozen columns, keyboard nav, inline editing, large-row virtualization). Every candidate is either (a) a UIKit grid on `UICollectionView`, (b) a thin SwiftUI layout helper, (c) a 0-to-150-star SwiftUI experiment, or (d) a source-available commercial product (NGTable).
2. The practitioner consensus on macOS (kean "Not List" 2021; Michael Tsai roundup April 2024; Apple forum threads 739849, 765653, 775695, 784845) is that SwiftUI `List`/`Table` degrade badly past a few thousand rows (hangs of 13 s on selection with 1,219 rows in one thread, "forever hang" at ~5,000 rows in another, macOS 15.5 regression reports), and people fall back to `NSTableView`.
3. The most borrowable techniques come from four places: the GPU glyph-atlas approach in NGTable, the `UIScrollView`+`LayoutEngine`+`ReuseQueue` architecture in SpreadsheetView, the pure-SwiftUI virtualization in DataGrid / Nil Coalescing's `OffsetLayout`, and the AppKit-hosting plumbing in flocked/AdvancedCollectionTableView.

## A. SwiftUI data grids and tables

### SwiftTabler (openalloc) — https://github.com/openalloc/SwiftTabler
145 stars, last push 2023-05-01, Apache-2.0, macOS 11+/iOS 14+, SwiftUI.
Does well: three interchangeable render strategies (`TablerList` on `List`, `TablerStack` on `ScrollView+LazyVStack`, `TablerGrid` on `LazyVGrid`) with the same column/row closures; header/footer sorting via `tablerSort` with configurable indicators; single/multi/no selection; bound-row variants so `TextField`s mutate the model; macOS hover; minimal `AnyView`; Core Data variants; row background/overlay; drag reorder in List variant.
Missing: column resizing/reordering, frozen columns, keyboard navigation, inline editing semantics beyond bound controls; horizontal scrolling needs the sibling SwiftSideways package (3 stars); README admits filtering with bound values "likely not scalable". Dormant since 2023.
Verdict: worth reading for its clean column-sort DSL and for a side-by-side demonstration of why List vs LazyVStack vs LazyVGrid each fail as a table substrate; not a base to build on.

### DataGrid (christopher-inegbedion) — https://github.com/christopher-inegbedion/DataGrid
0 stars, last push 2026-10-14, MIT, iOS 18 / macOS 15 / visionOS 2, pure SwiftUI.
Does well: single `ScrollView` with pinned header row, pinned first column and corner repositioned via `visualEffect` in the same render pass (no lagging second scroll view); lazy cell creation driven by `onScrollGeometryChange` mapping offset to visible row/column range (fires only when the set changes); index-based API (rows × columns, draw `(row, column)`), no array materialization; variable row heights via cached prefix sums + binary search in a SwiftUI-free `GridGeometry`; user-draggable column widths bound to `[CGFloat]`; single/multi cell selection; programmatic scroll-to-cell; VoiceOver row/column hints.
Missing: no sorting, inline editing, range/drag selection, drag-and-drop, keyboard navigation; VoiceOver only sees the materialized viewport; no benchmarks published; brand-new, single author.
Verdict: the best current demonstration that SwiftUI 2024+ APIs (`onScrollGeometryChange`, `visualEffect`) can do two-axis freezing without AppKit; steal the geometry/visible-range design even if the view is rewritten.

### swiftui-simple-table (darrarski) — https://github.com/darrarski/swiftui-simple-table
22 stars, last push 2023-06-20, MIT, iOS/macOS, SwiftUI. Shows all columns on compact iOS, horizontal + vertical scroll, sticky headers via `.simpleTableHeader()`, equal-width/height or aspect-ratio sizing. No sorting, selection, resizing or virtualization strategy described. Verdict: small, tidy; nothing structural to borrow beyond the sticky-header modifier.

### Layout "Grid" packages (not data tables)
- exyte/Grid — 2,122 stars, pushed 2026-09-15, MIT, iOS 14+/macOS 10.15+. CSS-Grid-style tracks (`.fr`, `.pt`, `.fit`), spans, explicit starts. No laziness, no headers, no selection.
- pietropizzi/GridStack — 658 stars, pushed 2022-02-21, MIT. Fixed-column flow grid.
- spacenation/swiftui-grid — 960 stars, archived, last push 2020-12-27.
- Q-Mobile/QGrid — 1,645 stars, last push 2020-08-05, MIT; effectively abandoned.
Verdict: track-sizing vocabulary in exyte/Grid (`fr`/`pt`/`fit`) is a good model for a column-width spec; otherwise irrelevant to tables.

### SwiftUIX — https://github.com/SwiftUIX/SwiftUIX
8,188 stars, pushed 2026-09-18, MIT, iOS 13+/macOS 11+. Provides `CocoaList` (UITableView bridge), `CocoaScrollView`, `CollectionView`. README does not document an NSTableView bridge or a multi-column Table component. Verdict: not a table; its hosting glue is iOS-centric.

### Not found / not notable
"LazyTableView", "SwiftyTable", "SwiftUI-Tables", "GridKit", "Sheetrock", "ReactiveTable", "Sheets" produced no notable repositories (only tutorial repos with 0-4 stars). "TablerView" is SwiftTabler. SparkBySam/Spark-Grid returns 404. Nil Coalescing's "custom lazy list" is a blog article (3 March 2025), not a package.

## B. AppKit (NSTableView / NSOutlineView) and bridges

### Apple's own baseline: SwiftUI `Table` + `TableColumnCustomization`
`TableColumnCustomization` (macOS 14+/iOS 17+) persists column order, visibility and width through `@SceneStorage`, keyed by `.customizationID`; on macOS users can reorder and hide/show columns. Column resizing exists on macOS. Known gaps per forum reports: performance collapse on large data, no frozen columns, no cell-level selection, limited keyboard/edit control. Verdict: any new table must match this API surface (sortOrder comparators, selection bindings, customization persistence) to feel native.

### flocked/AdvancedCollectionTableView — https://github.com/flocked/AdvancedCollectionTableView
55 stars, pushed 2026-09-04, MIT, macOS, AppKit (+SwiftUI cells).
Does well: ports of UIKit APIs to AppKit: `NSTableView.CellRegistration`, `NSContentConfiguration`, `NSHostingConfiguration` (SwiftUI inside `NSTableCellView`), `NSListContentConfiguration`, table/collection/outline diffable data sources with animated/non-animated apply, `reconfigureItems`, Backspace delete, Space Quick Look, reorder handlers, hover/prefetch handlers.
Missing: README says outline-view row dragging doesn't work and drag/drop out is inconsistent; "always use main branch"; one maintainer.
Verdict: the most complete open-source answer to "how do I host SwiftUI cells in NSTableView with diffable snapshots"; borrow the registration + hosting-configuration shape.

### ChimeHQ/Outline — https://github.com/ChimeHQ/Outline
25 stars, pushed 2024-09-14, BSD-3, macOS, `NSOutlineView` wrapped in SwiftUI with async lazy child loading, `expansion`/`selection` bindings, escape hatch to configure the raw `NSOutlineView`. Verdict: minimal but the cleanest model for a SwiftUI API over an AppKit tree view.

### kean "Not List" pattern (article + Pulse)
kean.blog/post/not-list (2021); kean/Pulse 7,246 stars, pushed 2026-10-11, MIT. `NSViewRepresentable` → `NSScrollView` → `NSTableView`, Coordinator as data source/delegate, plain AppKit row views (SwiftUI cells "didn't perform as well"), `reloadData` with manual selection restore, Combine publishers driving the table directly. Motivation: 150k rows made `List` unusable (undisableable diffing, janky scroll). Caveat: NSTableView wants row heights up front. Verdict: the canonical minimal bridge; still the fastest path to a performant macOS list.

### Michael Tsai roundup (2024-04-15) "NSTableView With SwiftUI"
Edvinas Byla replaced `LazyVGrid` with `NSTableView`: smoother scrolling, correct right-click selection semantics (SwiftUI `.contextMenu` does not select or identify the clicked row), free keyboard navigation and column rearranging, SwiftUI views kept in headers/cells. Stefan Pauwels: SwiftUI `Table` "has serious performance problems on macOS". Verdict: context-menu-selects-row and type-select are table-stakes behaviors a new table must reproduce.

### Open-source Mac apps with notable table UIs
- Sequel-Ace/Sequel-Ace — 7,559 stars, pushed 2026-10-27, MIT, Objective-C with some Swift. `Source/Views/TableViews` holds `SPTableView`, `SPCopyTable`, `SATableHeaderView`, `SAFieldEditorCommitPolicy.swift`, plus recent "filter columns to display in content view". Verdict: study it for inline-edit commit policy, copy-as-TSV/SQL, and column visibility filtering in a real NSTableView grid.
- HexFiend/HexFiend — 5,910 stars, pushed 2025-06-29, BSD-2. Custom-drawn column representers handling 118 GB files without loading into memory. Reference for byte-range windowed data sources.
- Ranchero-Software/NetNewsWire — 10,489 stars, pushed 2026-10-25, MIT, Swift; timeline on NSTableView/NSOutlineView. CotEditor — 8,637 stars; NSOutlineView outline navigator. PostgresApp — 7,787 stars; minimal table UI. mikekazakov/nimble-commander — 753 stars, GPL-3.0, C++; custom-drawn dual-pane file lists.
- Closed source but widely admired, UX references only: TablePlus, Postico, ForkLift, Marta, Proxyman, Nova. Beekeeper Studio is Electron (skipped). DB Browser for SQLite is Qt/C++ (skipped).
- BunnyGrid (matthfaria96) — 0 stars, pushed 2026-10-25, AGPL-3.0, Swift/SwiftUI macOS 14+ DB client with paginated grid; too new to assess, AGPL.

## C. Spreadsheet-grade

### SpreadsheetView — https://github.com/bannzai/SpreadsheetView (canonical, 3,535 stars, pushed 2024-05-10, MIT)
The kishikawakatsumi/SpreadsheetView URL now points to a 60-star repo last pushed 2020-10-08; the high-star project lives under bannzai. UIKit, iOS 9+. Does well: frozen rows and columns via data-source counts, merged cells (`CellRange`), per-cell gridlines/borders, circular infinite scrolling, `UICollectionView`-like API, "fast scrolling, memory efficient". Source layout confirms a dedicated `LayoutEngine.swift`, `ReuseQueue.swift`, `ScrollView.swift`, `Gridlines.swift`/`Borders.swift`, `Array+BinarySearch.swift`.
Missing: iOS only, no macOS/AppKit, no sorting, no built-in editing, dormant 17 months.
Verdict: the reference architecture for a spreadsheet grid: separate layout engine, reuse queue, binary-searched column/row offsets, frozen panes as separate scroll regions. Port the design, not the code.

### SwiftDataTables (pavankataria) — https://github.com/pavankataria/SwiftDataTables
461 stars, pushed 2026-02-11, MIT, iOS, UIKit (`UICollectionView` subclass). Does well: type-safe key-path columns, animated diffing (`setData(_:animatingDifferences:)`), self-sizing rows claimed efficient at 100k+ rows ("50,000 rows in 0.25 s, was 4+ minutes"), frozen left/right columns, built-in sort (number/string aware) and search. Missing: macOS, keyboard nav, inline editing; 0.x versioning. Verdict: borrow the column declaration API and the diff-then-apply update model.

### SwiftGridView (nlampi) — https://github.com/nlampi/SwiftGridView
67 stars, pushed 2026-09-09, MIT, iOS 15+, UIKit with `SwiftGrid` SwiftUI wrapper. Does well: frozen columns and rows, sticky section headers, grouped (spanning) headers, row/cell/multi selection, pinch-zoom with per-axis column-width/row-height scaling, Swift 6 strict-concurrency `@MainActor` API. Missing: macOS, sorting, editing. Verdict: grouped-header and axis-zoom ideas are worth lifting.

### NGTable — https://github.com/ngtable/NGTable
1 star, pushed 2026-10-15, PolyForm Noncommercial + paid commercial license (business use including internal tools requires a license), macOS 14+/iPadOS 17+, Swift 6.2, AppKit+UIKit with SwiftUI `NGDataTable` on macOS. Source mostly open; ships an XCFramework and optional NGTableICU binary.
Does well (per README; benchmarks self-reported, Release build, Apple silicon): Metal-rendered cells from a Core Text-shaped glyph atlas so value changes need no rasterization; frozen leading/trailing columns, column groups, resize/move/hide/show with saved layouts; summary row with formulas and background summarizing; multi-level grouping with subtotals; search/filter without mutating the source; targeted reload/insert/remove/move with selection following record identity; context menus, keyboard nav, type-select, copy to spreadsheets, VoiceOver; wrapping text rows; iPad in-place editing. Claims 120 fps at 20,000 rows / 45,000 changes/s where NSTableView drops to 17 fps and SwiftUI Table to 3 fps.
Missing: license excludes business use; PRs not accepted; must not be nested in another scroll view; Mac inline editing not clearly documented; single author, unproven adoption.
Verdict: the most ambitious design in the field and the only one that attacks the real macOS problem (live updates at scale); study the glyph-atlas renderer, identity-stable selection and in-table sort/filter pipeline, but do not depend on it.

### SimpleSpread (baudehlo) — https://github.com/baudehlo/SimpleSpread
14 stars, pushed 2026-10-28, MIT, Swift, macOS 14+ and iPad. Grid built from scratch (rendering tech not documented); Excel Ready/Enter/Edit keyboard state machine, F2/double-click edit, Cmd+arrow data-edge jumps, freeze panes/top row/first column, header resize with autofit, hide/unhide rows, fill handle with formula translation, per-gesture undo, 25-400% zoom, 1,048,576-row sheets, 100 MB CSV in 1.5 s. Verdict: the best open Swift spec of spreadsheet keyboard/editing semantics on the Mac.

### Figures (tariknaeem) — https://github.com/tariknaeem/Figures
0 stars, pushed 2026-10-18, MIT, SwiftUI macOS+iOS xlsx app. Frozen header rows, column/row resize, autofill, name box; frozen columns explicitly unsupported; rendering approach not documented. Verdict: too early; watch.

No open-source Metal/Canvas-rendered Swift grid other than NGTable was found. nanbu/SwiftSheets is a formula/file library with no view component.

## D. UIKit list engines (iOS)

- Instagram/IGListKit — 13,081 stars, pushed 2026-10-23, MIT, Objective-C with Swift interop; iOS 11+/tvOS; macOS limited to the diffing component. Section-controller architecture, decoupled `IGListDiff`.
- airbnb/epoxy-ios — 1,317 stars, pushed 2026-10-25, Apache-2.0, Swift, UIKit only. Declarative `CollectionViewController` items with `dataID`/content/style, `setItems(_:animated:)`, EpoxyLayoutGroups.
- TextureGroup/Texture — 8,178 stars, pushed 2026-10-23, Objective-C++, async layout/rendering off main thread.
- ra1028/Carbon — 1,355 stars, pushed 2024-07-13, Apache-2.0; component DSL on UITableView/UICollectionView via DifferenceKit.
- ra1028/DifferenceKit — 3,666 stars, pushed 2026-06-23, Apache-2.0; O(n) Heckel diff with section support. ra1028/DiffableDataSources — 858 stars. lxcid/ListDiff — 240 stars, dormant 2020. jflinter/Dwifft — 1,845 stars, dormant 2023. onmyway133/DeepDiff — archived. tonyarnold/Differ — 676 stars, dormant 2022.
- maxsokolov/TableKit — 700 stars, pushed 2023-04-19, MIT; type-safe declarative UITableView rows. bcylin/QuickTableViewController ~557 stars (static settings tables).
- apple/swift-collections — 4,527 stars, pushed 2026-10-27, Apache-2.0; `OrderedDictionary`/`OrderedSet` are the right backing store for id→row and ordered selection.
Verdict: the durable ideas are (1) decoupled O(n) diffing applied as batch updates, (2) section/row identity by `dataID`, (3) Texture's off-main-thread measurement. All are iOS-only frameworks; none ship a multi-column grid.

## E. Virtualization notes for SwiftUI on macOS

- `List` is lazy only when SwiftUI can count a `ForEach` element's rows without evaluating the closure; `if` inside `ForEach` and `AnyView` wrappers defeat it (Apple forum, WWDC23 guidance). On macOS, one forum report says `List` still called init/body for every row.
- `ScrollView + LazyVStack` loads lazily but does not release views; one iOS test (STRV, Jan 2025) measured 5.5 s scroll-to-bottom for `List` vs 52 s for `LazyVStack` with heavy rows.
- Nil Coalescing (2025-03-03): a recycling list using `ScrollView` + `onScrollGeometryChange` + a custom `Layout` (`OffsetLayout`) with a `LayoutValueKey` carrying the real index and fragment IDs = index mod visible-count so SwiftUI reuses views; fixed row height only; recycled `@State` must be reset `onChange(of: id)`.
- `NSHostingView` in `NSTableCellView`: Apple docs note hosting views add min/intrinsic/max constraints by default and that disabling them via sizing options helps performance (macOS 13+). `UIHostingConfiguration` is the iOS 16 equivalent.

## Top 10 worth studying, ranked

1. NGTable — Metal glyph-atlas text rendering, in-table sort/filter/summary pipeline, selection keyed to record identity across reloads, NSTableView-shaped API with a SwiftUI `Table`-style facade. License forbids reuse; study only.
2. NSTableView bridging corpus: kean "Not List" + flocked/AdvancedCollectionTableView — `NSViewRepresentable` + Coordinator, `CellRegistration`, `NSHostingConfiguration`, diffable snapshots with non-animated apply, Quick Look/Backspace conventions.
3. SpreadsheetView (bannzai) — separate `LayoutEngine`, `ReuseQueue`, binary-searched offsets, frozen panes and merged cells as first-class layout concepts.
4. DataGrid (christopher-inegbedion) — pure SwiftUI two-axis pinning via `visualEffect`, visible-range via `onScrollGeometryChange`, SwiftUI-free `GridGeometry` with prefix sums.
5. Nil Coalescing OffsetLayout article — fragment-ID view recycling with a custom `Layout`.
6. SwiftDataTables — key-path column declaration, diff-then-apply updates, self-sizing claims at 100k rows, left/right frozen columns.
7. SwiftGridView — grouped (spanning) headers, per-axis pinch zoom, strict-concurrency `@MainActor` data-source design.
8. SwiftTabler — three substrate strategies side by side, concise sort-indicator DSL, bound-row editing variants.
9. IGListKit + DifferenceKit (+ Epoxy, Texture) — section-controller decomposition, O(n) Heckel diffing, async off-main measurement.
10. SimpleSpread + Sequel Ace — Excel-grade keyboard state machine and real-world NSTableView grid subclasses.

Baseline to match, not borrow: Apple `Table` + `TableColumnCustomization` (macOS 14) API surface, and the context-menu-selects-row / type-select / keyboard behaviors users get for free from NSTableView.
