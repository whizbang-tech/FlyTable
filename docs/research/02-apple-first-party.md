# Apple first-party table/grid technology, state of play as of October 2026

Scope: macOS 26 Tahoe / iOS 26 SDKs plus what WWDC26 (June 2026, macOS 27) announced. Availability figures were read from the Apple doc page's metadata unless flagged otherwise. Forum and blog claims are cited as such.

## 1. SwiftUI `Table`

### Core API (verified on Apple docs)
- `Table` — macOS 12+, iOS/iPadOS 16+, visionOS 1+. Generic over `Value, Rows: TableRowContent, Columns: TableColumnContent`. Columns built by `@TableColumnBuilder`, rows by `@TableRowBuilder`.
- Initializer families: `init(_:columns:)`, `init(_:selection:columns:)`, `init(_:sortOrder:columns:)`, `init(of:columns:rows:)` (static rows), `init(_:columnCustomization:columns:)`, hierarchical `init(_:children:…)`.
- `TableColumn` — width: `.width(_:)` (fixed, not user resizable), `.width(min:ideal:max:)` (resizable). Sortable inits take `value:` key paths, `comparator:` or `sortUsing:`.
- `TableColumnBuilder` — `buildBlock` overloads up to ten columns; `buildIf`, `buildEither`, `buildLimitedAvailability` exist.
- `TableColumnForEach` — iOS 17.4 / macOS 14.4: dynamic columns from identified data.
- `TableColumnAlignment` — iOS 17 / macOS 14: `.leading/.center/.trailing/.numeric/.numeric(_:)`; applies to header and default content alignment.
- Sorting: bind `sortOrder: Binding<[some SortComparator]>`; "the table itself doesn't perform a sort operation".
- Selection: bind `Optional<ID>` for single, `Set<ID>` for multi.
- `tableStyle(_:)` with `AutomaticTableStyle`, `InsetTableStyle`, `BorderedTableStyle` (macOS only). `.alternatingRowBackgrounds(_:)` (macOS 14+) supersedes the `alternatesRowBackgrounds:` style arguments.
- `tableColumnHeaders(_:)` — iOS 17 / macOS 14; hides the global header; does not affect `Section` headers.
- `TableColumnCustomization<RowValue>` — iOS 17 / macOS 14. Enables column reordering and visibility, bindable to `@SceneStorage`/`@AppStorage` (Codable). Requires `.customizationID(_:)` per column. `resetOrder()` preserves visibility and size. `TableColumnCustomizationBehavior` + `.disabledCustomizationBehavior(_:)` and `.defaultVisibility(_:)`.
- Rows: `TableRow`, `DisclosureTableRow` (iOS 17 / macOS 14), `TableOutlineGroupContent` from `init(_:children:)`, `Section` inside the rows builder, `TableHeaderRowContent`.
- Row interactions on `TableRowContent`: `.contextMenu(menuItems:)`, `.contextMenu(menuItems:preview:)`, `.draggable(_:)`, `.dropDestination(for:action:)` (iOS 17 / macOS 14), `.onHover(perform:)` (macOS 14).
- Container-level `contextMenu(forSelectionType:menu:primaryAction:)` — iOS 16 / macOS 13; receives the selected ID set (empty set = empty area); double click performs the primary action on macOS.
- Platform behaviour: macOS scrolls horizontally when columns overflow; iPad does not. In a compact horizontal size class the table hides headers and all columns after the first.
- Programmatic scroll: `ScrollViewReader` + `proxy.scrollTo(id)` works on macOS Table (forum 723637).

### WWDC25 / WWDC26: nothing Table-specific
WWDC25 "What's new in SwiftUI" (256) did not mention `Table`; it claimed macOS `List`s of 100k+ items load up to 6x faster and update up to 16x faster, plus better frame scheduling and a SwiftUI performance Instrument. The WWDC26 session (269) again contains no `Table` API; the new `.reorderable()` / `.reorderContainer(for:)` is for `List`/`LazyVGrid`, and `.swipeActionsContainer()` extends swipe actions to any scroll view. Michael Tsai: the quoted speedups come from scheduling/lazy loading, not an architectural change (mjtsai, June 2025).

### Known limitations and bugs of `Table` (with citations)
1. Row height is locked on macOS; no row-height API (fatbobman "Table in SwiftUI"; itsuki, Medium). iPadOS sizes rows to content, so behaviour differs by platform.
2. Column widths are not persisted and cannot be read or set. Apple DTS, Feb 2025: resizing + restoring widths is "currently not supported" (forum 774105). `TableColumnCustomization` only covers order and visibility.
3. Header styling limits: only `tableColumnHeaders(.hidden)` and `TableColumnAlignment`; no header font, height, background or custom header view.
4. No grid lines / divider styling, no frozen or pinned columns, no horizontal scrolling on iPad (useyourloaf; WWDC22 10058).
5. Sections are not sticky group rows on macOS (Helge Heß via mjtsai, May 2023).
6. Performance at scale / regressions: macOS 15.5 regression, tables that scrolled fine on 15.4.1 hang and beachball on 15.5, still worse on macOS 26 in July 2025 (forum 784845). Tahoe: memory stays high with a bounded 1,000-record deque (FB21850924) and performance degrades quickly until a view switch or window resize (FB21860141) (mjtsai, Feb 2026). 13-second hang selecting one of 1,219 rows on macOS 14; root cause an `if` inside the rows `ForEach` (forum 739849). WWDC23 10160: all IDs are gathered eagerly; a conditional or `AnyView` per element defeats on-demand row creation. No cell recycling (Majid Jabrayilov, WWDC 2026 wish lists).
7. Sorting quirks: Table never sorts; `Bool`/optional key paths fail for Swift structs; only key-path columns sort (useyourloaf; forum 749180).
8. Selection/focus bugs: multi-selection broke on iPadOS 18 / Catalyst (FB15280607) (forum 764624). On macOS 27, `List`/`Table` reportedly never become first responder on click (mjtsai, Oct 2026).
9. Context menus: `.contextMenu` on cell content only hit the text and `TableColumn` has no `.contextMenu` (forum 697936); SwiftUI's `.contextMenu` doesn't select the right-clicked item (Byla via mjtsai, Apr 2024). `contextMenu(forSelectionType:)` fixes most of this.
10. Ten-column `buildBlock` cap; heavy generics give "failed to produce diagnostic" errors.
11. Layout quirks: inside a grouped `Form` the table is capped at 600pt on macOS 15 (forum 764602); compact size class collapses to one column.
12. Accessibility: no verified Table-specific VoiceOver defect reports found; macOS `Table` inherits `NSAccessibilityTable` semantics but per-cell header relationships cannot be customised from SwiftUI.

## 2. SwiftUI `List` on macOS
- Styles: `.automatic`, `.inset`, `.bordered`, `.plain`, `.sidebar`; `.alternatingRowBackgrounds()` works on all but `.sidebar`. HIG: macOS defines a bordered style that uses alternating row backgrounds for large tables.
- Performance: macOS `List` calls init and body of every row (forum 704778). Sarah Reichelt: 10,000-row sidebar took 50+ s to appear on an M3 iMac; `Equatable` row + `.equatable()` fixed it (troz.net 2024). Kean rewrote Pulse's 150k-row list on `NSTableView` because SwiftUI's diffing can't be disabled and macOS needs every row height up front.
- Why people fake tables with `List` + `HStack`: selection, keyboard navigation and `contextMenu(forSelectionType:)` for free, with control over row height, padding and separators. You lose headers, sorting UI, column resizing/reordering, and must hard-code column widths. Natalia Panferova's `RecyclingScrollingLazyView` (fixed row height, `onScrollGeometryChange`, custom `Layout`, fragment-ID recycling) is the SwiftUI-only answer when `List` is too slow.

## 3. `LazyVGrid` / `LazyHGrid` / `Grid`
- `LazyVGrid` is lazy only along the scroll axis: no column virtualization; `pinnedViews` pins only section headers/footers (swiftui-lab). Row-height mismatch and baseline-alignment bugs when used as a table (forums 705341, 694013).
- `Grid`/`GridRow` (iOS 16) is non-lazy and `GridRow` is not a true row for interaction (fatbobman).
- Edvinas Byla shipped an invoice list on `LazyVGrid`, found scrolling "okayish" and context menus wrong, and replaced it with `NSTableView` (byla.lt).

## 4. AppKit `NSTableView` / `NSOutlineView`, the reference implementation
- View-based cells since 10.7: `makeView(withIdentifier:owner:)`, `register(_:forIdentifier:)`, `rowView(atRow:makeIfNecessary:)`, `view(atColumn:row:makeIfNecessary:)`, `didAdd/didRemove(_:forRow:)`.
- Row height: `rowHeight` (default 16.0, used only with `RowSizeStyle.custom`), `tableView(_:heightOfRow:)`, `usesAutomaticRowHeights`, `noteHeightOfRows(withIndexesChanged:)`, `rowSizeStyle` (`.default/.small/.medium/.large/.custom`). Known wart: auto-height rows grow but don't shrink (forum 696976).
- Columns: `allowsColumnReordering`, `allowsColumnResizing`, `allowsColumnSelection`, `columnAutoresizingStyle`, `sizeLastColumnToFit()`, `autosaveName` + `autosaveTableColumns`, `sortDescriptors`, `highlightedTableColumn`, `setIndicatorImage(_:in:)`.
- Header: `headerView: NSTableHeaderView?`, `cornerView`, `NSTableHeaderCell` (override `drawInterior(withFrame:in:)`, `drawSortIndicator(withFrame:in:ascending:priority:)`, `sortIndicatorRect(forBounds:)`).
- Style: `NSTableView.Style` (macOS 11) `.automatic/.fullWidth/.inset/.sourceList/.plain`, `effectiveStyle`. WWDC20 10104: automatic resolves to sourceList in a sidebar, fullWidth in a bordered scroll view, otherwise inset; inset adds horizontal padding, a slightly taller default row height and wider spacing in multicolumn tables.
- Appearance: `usesAlternatingRowBackgroundColors`, `backgroundColor`, `gridStyleMask`/`gridColor`, `intercellSpacing`, `drawGrid(inClipRect:)`, `drawBackground(inClipRect:)`.
- Group/floating rows: `floatsGroupRows` (default on), delegate `tableView(_:isGroupRow:)`; `NSTableRowView.isGroupRowStyle`, `isFloating`.
- Selection drawing: `NSTableRowView.isSelected`, `isEmphasized`, `isNextRowSelected`/`isPreviousRowSelected`, `interiorBackgroundStyle`, `drawSelection(in:)`, `drawSeparator(in:)`, `drawBackground(in:)`, `drawDraggingDestinationFeedback(in:)`.
- Drag & drop: `setDraggingSourceOperationMask(_:forLocal:)`, `draggingDestinationFeedbackStyle`, `setDropRow(_:dropOperation:)`, `verticalMotionCanBeginDrag`, `registerForDraggedTypes`, data source `pasteboardWriterForRow`/`acceptDrop`.
- Updates: `beginUpdates()`/`endUpdates()`, `insertRows(at:withAnimation:)`, `removeRows(at:withAnimation:)`, `moveRow(at:to:)`, `hideRows/unhideRows(at:withAnimation:)`, `NSTableView.AnimationOptions`, `reloadData(forRowIndexes:columnIndexes:)`, `noteNumberOfRowsChanged()`.
- Type-select: `allowsTypeSelect` + delegate `tableView(_:typeSelectStringFor:row:)`. Row actions: `rowActionsVisible`, `tableView(_:rowActionsForRow:edge:)`. Quick Look via `quickLook(with:)` / `QLPreviewPanel`.
- `NSTableViewDiffableDataSource<Section, Item>` — macOS 11.0+ (not 10.15.1); `init(tableView:cellProvider:)`, `rowViewProvider`, `apply(_:animatingDifferences:)`.
- `NSOutlineView`: `outlineTableColumn`, `indentationPerLevel`, `indentationMarkerFollowsCell`, `autosaveExpandedItems`, `expandItem/collapseItem(_:expandChildren:)`, `insertItems(at:inParent:withAnimation:)`, `moveItem`, `stronglyReferencesItems`, tint via `outlineView(_:tintConfigurationForItem:)`.
- `NSCollectionViewCompositionalLayout` — macOS 10.15; no AppKit equivalent of UIKit's `list(using:)`, so it suits grids, not sortable column tables.
- Current Tahoe bug: content scrolls under the header unless the table is inset ~1pt from its container; a bordered `NSScrollView` also breaks the toolbar blur (Reichelt/Webster via mjtsai Feb 2026).

### Hosting NSTableView in SwiftUI and SwiftUI in cells
- `NSViewRepresentable` wrapping `NSScrollView`+`NSTableView`; coordinator is data source/delegate; `updateNSView` reloads, restores selection, scrolls (Kean; Byla).
- Apple's cell guidance (WWDC22 10075): use a single hosting view and update it with a different root view when the cell's content needs to change; avoid adding and removing subviews from the cells as the user scrolls.
- `NSHostingSizingOptions` — macOS 13: `.minSize`, `.intrinsicContentSize`, `.maxSize`, `.standardBounds`, `.preferredContentSize`. Default is all three; disable for performance. Brian Webster: the hosting view probes the root view with 0×0, ∞×∞ and nil proposals on every refresh to build constraints.
- Pitfalls: reuse identifiers must be set in code or hosting views accumulate; `NSHostingView` stored in an `NSTableHeaderCell` crashes during column reorder; header `init(textCell:)` needs a non-empty string; grid lines draw in empty tables (byla.lt). SwiftUI-positioned content offsets hit-testing (forum 759081); `NSHostingView` item views glitch the `NSOutlineView` disclosure indicator (forum 806087); `TimelineView` inside a hosting view churns Auto Layout (forum 773682); `NSViewRepresentable` updates ignore SwiftUI animations.

## 5. UIKit on iOS/iPadOS
- `UIHostingConfiguration` — iOS 16: `init(content:)`, `.background(_:)`, `.margins(_:_:)`, `.minSize(width:height:)`; in a list layout, swipe actions and separator alignment bridge automatically. Apple engineer: it is the only officially supported way to render SwiftUI content inside collection and table view cells (forum 719445).
- `UICollectionViewListCell` — iOS 14: `accessories`, `indentationLevel/Width`, `separatorLayoutGuide`, `defaultContentConfiguration()`. Lists via `UICollectionLayoutListConfiguration`, `NSCollectionLayoutSection.list(using:layoutEnvironment:)`; mix list and grid sections, orthogonal scrolling for horizontal column overflow. Diffable data source + `UICollectionViewListCell` is the iPad "table" when SwiftUI `Table` can't scroll horizontally.

## 6. 2023–2026 SwiftUI APIs relevant to building a table

| API | Availability | Use |
|---|---|---|
| `Layout` protocol | iOS 16 / macOS 13 | custom column layout, pass indices via `LayoutValueKey` |
| `onGeometryChange(for:of:action:)` | iOS 16 / macOS 13 (back-deployed) | measure cells/columns without `GeometryReader` |
| `scrollPosition(id:)`, `scrollTargetBehavior`, `scrollTargetLayout`, `containerRelativeFrame`, `visualEffect` | iOS 17 / macOS 14 | scroll anchoring, column sizing, cheap per-row effects |
| `onScrollGeometryChange`, `ScrollGeometry`, `onScrollPhaseChange` | iOS 18 / macOS 15 | visible-range computation for row recycling |
| `TextRenderer`, `Text.Layout` | iOS 17 / macOS 14 (`sizeThatFits` iOS 18) | custom glyph drawing, truncation effects |
| `Canvas` | iOS 15 / macOS 12 | draw grid lines/dividers in one pass |
| `@Observable` | iOS 17 / macOS 14 | per-property invalidation; `@State` macro (WWDC26, back-deployed) initialises stored classes once |
| `glassEffect()`, `ToolbarSpacer`, scroll-edge effect, `windowResizeAnchor` | macOS 26 | Liquid Glass toolbars over tables |
| `draggable(containerItemID:)`, `dragContainer(for:selection:)`, `DragConfiguration`, `dragPreviewsFormation` | macOS 26 | multi-item row drags |
| `.reorderable()`, `.reorderContainer(for:)`, `.swipeActionsContainer()`, `ContentBuilder`, `appearsActive` | macOS 27 | not for `Table`; most new APIs don't offer backward compatibility |

## 7. Apple's own apps as reference art
HIG macOS guidance: click a heading to sort and reverse on second click; let people resize columns; consider alternating row colors in a multicolumn table; use an outline view for hierarchy; descriptive Title Case column headings. Big Sur introduced the inset selection style with extra horizontal padding and taller default rows; sidebars always use `sourceList`; Apple publishes no point values. `rowHeight` defaults to 16pt; `small/medium/large` track the system font's line height. Mail uses `indicatorImage(in:)` for the sort chevron. Finder list view has no user row-height setting; Tahoe's list view does not remember the Name column width (TidBITS, Jan 2026).

Unverified design observations (measure before relying on them): Finder/Mail/Activity Monitor list rows sit in the roughly 20–24pt band for the medium row size (taller in Tahoe's inset style), 1px hairline separators or alternating `.alternatingContentBackgroundColors`, ~11pt small-system-font bold headers with the sort chevron trailing in the sorted column, inset rounded selection in `.selectedContentBackgroundColor` (accent) when emphasized and `.unemphasizedSelectedContentBackgroundColor` (grey) when not first responder, headers that float above scrolled content, group rows (Mail, Xcode navigator) that float. Numbers uses its own canvas renderer, not `NSTableView`.

## What a best-in-class SwiftUI-facing table must do that Apple's `Table` doesn't
1. Own row geometry: row height (fixed, per-row, or measured-and-cached), row/column spacing and insets.
2. Expose and persist column width: read/write widths, observe live resizes, persist widths alongside order/visibility, min/ideal/max plus fit-to-content.
3. Stylable header and dividers: header height, typography, background, custom header views, sort indicator styling, grid lines/separators, per-column alignment.
4. Frozen columns and horizontal scrolling everywhere, with a controlled compact-width strategy.
5. Sticky sections / group rows as in `NSTableView.floatsGroupRows`.
6. Predictable performance at 10k–1M rows: row-view recycling, fixed-or-cached heights, no eager ID gathering, immunity to conditionals inside `ForEach`, no memory growth, no per-OS regressions.
7. Correct Mac behaviour out of the box: right-click selects before the menu, double-click primary action, type-select, Quick Look, full keyboard navigation, first responder on click, drag-and-drop feedback.
8. Inline editing with commit semantics.
9. Complete sorting: multi-key indicators, `Bool`/optional/custom comparators on plain structs, optional built-in sorting.
10. Dynamic and many columns without the ten-column cap, plus a column picker UI.
11. Cross-platform fidelity and an auditable accessibility tree.
12. Design parity with Finder/Mail delivered as options rather than fixed defaults.

Key sources: Apple docs for Table, TableColumn, TableColumnBuilder, TableColumnCustomization, tableColumnHeaders, alternatingRowBackgrounds, DisclosureTableRow, contextMenu(forSelectionType:), NSTableView, NSTableView.Style, NSTableRowView, NSTableHeaderCell, NSOutlineView, NSHostingSizingOptions, UIHostingConfiguration, UICollectionViewListCell, HIG Lists and tables. WWDC 20/10104, 22/10058, 22/10075, 23/10160, 25/256, 26/269. Community: fatbobman, useyourloaf, kean.blog, byla.lt, troz.net, nilcoalescing, brian-webster.net, mjtsai.com (2024-04-15, 2025-06-18, 2026-02-03, 2026-02-05, 2026-06-03, 2026-10-20), Apple forums 739849, 764624, 774105, 775695, 784845, 697936, 723637, 850470.
