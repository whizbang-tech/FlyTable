# High-performance tables on Apple platforms (Swift, SwiftUI API): research report

Scope: 100k–1M rows, 10–50 columns, 120Hz scrolling, optional variable heights, macOS-first with iOS. Claims are tagged with what backs them; several "SwiftUI is slow at N rows" items are single forum reports, not controlled benchmarks.

## 1. Virtualization strategies

What SwiftUI containers are backed by (verified via SwiftUI-Introspect source):
- `List`: `UITableView` on iOS 13–15, `UICollectionView` on iOS 16+, `NSTableView` on macOS 10.15+.
- `Table`: `NSTableView` on macOS 12+, `UICollectionView` on iOS 16+/visionOS.
- `ScrollView`: `NSScrollView` on macOS, `UIScrollView` on iOS.

What List/Table do with your data (WWDC23 "Demystify SwiftUI performance", 10160): identifiers are gathered eagerly for every element; row content is built on demand for the visible region plus a buffer; this laziness holds only if each element resolves to a constant number of views. An `if` without `else` or `AnyView` inside `ForEach` forces every row to be built. From iOS 17/macOS 14, `ForEach(data)` in `rows:` identifies rows by element ID. Confirmation: a 1,000-row macOS `Table` took 900 ms–3.5 s per selection change; ~200 ms was the `rows:` `ForEach` re-running for all rows because of an `if` inside it (forum 739849).

Field reports on SwiftUI `List`/`Table` at scale (anecdotal, mostly macOS):
- Hierarchical `List`, 100k items, release build: iPhone 13 Pro ~6 s to render, ~8 s per selection; Mac Studio M2 "minutes" before responsive; equivalent `NSOutlineView`/`UICollectionView` demos fine; FB14822105 (forum 761829).
- `Table`, 5,000 rows loads fine but any data update hangs "minutes" on macOS (forum 765653).
- `Table` with `TableColumnForEach`, ~200 rows × 150 columns "unusable"; NSTableView + NSTextField cells "great" (forum 692367).
- macOS 15.5 regressed `Table` scrolling to beachballs even with three text columns (forum 784845).
- macOS `List` evaluated `init`/`body` for all 101 rows in 2022; `LazyVStack` did not (forum 704778).
- Kean (Pulse), ~150k rows: `List`'s automatic diffing cannot be disabled and dominated reload time; rewrote as `NSTableView` in `NSViewRepresentable` (~300 lines) (kean.blog/post/not-list).
- Apple's own numbers: WWDC25 says macOS lists of >100k items load 6x faster and update up to 16x faster in the 26 release, plus improved update scheduling (WWDC25 256). An Apple engineer says `DisclosureGroup`-in-`List` got fixes in macOS 27 (forum 832946). 1M rows × 50 columns is far beyond what anyone reports working.

`LazyVStack` in `ScrollView`: lazy creation, but content height is estimated from nearby rows; rapid far scrolling must evaluate bodies of all earlier rows; large height variance causes blank areas or jumps (fatbobman). Bartlett (iPhone 15 Pro, iOS 18.3) reproduces the height-estimation failure: dragging the indicator made scrolling jump and spiked memory; fixed-height cells gave minor drops only (Jacob's Tech Tavern). Off-screen lazy views are discarded and `@State` is lost despite stable identity (Swift Forums pitch). STRV's benchmark (1,001 heavy rows, iPhone 15 Pro, iOS 17.5): `List` 5.53 s to scroll to bottom, 4.6 hangs, memory 114→129→118 MB; `LazyVStack` 52.3 s, 78 hangs, 90→149→152 MB.

UICollectionView/NSTableView recycling: `dequeue` returns a pooled cell after `prepareForReuse`; iOS 15+ prefetches cells. `NSTableView` recycles rows but does not virtualize columns: every visible row instantiates a cell view per column, which is why wide tables degrade. Since macOS 13, view-based NSTableView estimates row heights when `heightOfRow` is implemented; Ventura 13.0 shipped a stale-height cache bug after `reloadData()`; opt-out is `NSTableViewCanEstimateRowHeights` (Tietze).

Pure custom virtualization (SwiftUI shell): Nil Coalescing's recipe: `ScrollView` + `onScrollGeometryChange` → `visibleRect` → row range, a custom `Layout` whose `sizeThatFits` returns `rowHeight × count` and places rows at `index × rowHeight`, and row identity = `index % visibleCount` so SwiftUI keeps a fixed pool of row views (reset `@State` on data-ID change). `onScrollGeometryChange` is iOS 18/macOS 15+; the `transform` runs every offset change and `action` only when the result changes; only the first scroll view in the hierarchy is observed. For variable heights, a Fenwick tree over row heights gives O(log n) prefix-sum and O(log n) offset→row inverse with O(log n) point updates, versus a flat prefix array (O(1) read, O(n) rebuild). Unmeasured rows use estimates corrected on render. Horizontal column virtualization is the same math on column widths; nothing in AppKit or SwiftUI does it for you.

## 2. Rendering strategies

| Strategy | Perf ceiling (est.) | Fidelity / native feel | Accessibility | Effort | Evidence |
|---|---|---|---|---|---|
| (a) SwiftUI view per cell (`Table`, `List`, LazyVStack+HStack) | Low–medium: ~1k rows × 10 cols already produces selection hangs; Table updates hang at 5k on macOS | Highest | Free | Lowest | forums 739849, 765653, 692367; WWDC23 identity rules |
| (b) SwiftUI view per row, pooled rows via custom `Layout` | Medium–high: ~60 visible rows × pool; SwiftUI cost is O(visible) | Good; cells lose per-cell hit testing unless added | Manual `accessibilityChildren`/rotor | Medium | nilcoalescing recipe |
| (c) SwiftUI `Canvas` for whole viewport | High for drawing; `Canvas` in `ScrollView` redraws on every scroll event; `drawingGroup` re-rasterizes the whole view on any change | Text via `GraphicsContext.resolve` is real text; no system selection look | Synthesized | Medium | HWS forum 25306; Juniper Photon |
| (d) Custom `NSView`/`UIView` document view, Core Text `CTLine` cache, draw only `dirtyRect`, layer-backed, `canDrawConcurrently` | Highest practical: O(visible cells), 1M rows trivially; proven pattern | Fully controllable; must reimplement selection, focus rings, hover | `NSAccessibilityElement` tree per visible cell/row | High | cocoa-dev CTLine threads; `canDrawConcurrently` docs; Glide (web analog) |
| (e) Metal glyph-atlas grid | Highest raw throughput; text pipeline is a project of its own | Hard to match system text rendering | Fully synthesized | Very high | metalbyexample; forum 651229 |
| (f) View-based `NSTableView` with `NSHostingView` cells | Medium: rows recycle, but each column instantiates a hosting view + SwiftUI graph | High | Free | Medium | mjtsai 2024-04-15; forum 679850 |
| (g) View-based `NSTableView` with `NSTextField` cells | High for ≤~20 columns; 1M rows fine | Native | Free | Medium | forum 692367; kean; FastList |
| (g′) Cell-based `NSTableView` (deprecated) | Historically fastest; legacy only | Dated | Partial | Low | cocoa-dev 2017 |

Notes: no documented AttributeGraph node cap; the failure mode is over-invalidation (Eidhof). `drawingGroup()` renders to an offscreen Metal image and re-rasterizes the whole subtree on any change, so it is wrong for scrolling text (Theodo). Glide Data Grid is the reference for (c)/(d): canvas-drawn, cells rendered lazily on demand, native scrolling, `updateCells` partial redraw, `freezeColumns`, `rowHeight` as a function, "millions of rows".

## 3. Text layout cost
- Creating a `CTTypesetter`/`CTLine` is the expensive step; cache the `CTLine` per cell and only `CTLineDraw` in `draw(_:)`; `NSStringDrawing` caches layout and can win for short strings (cocoa-dev 2015, 2010).
- Measuring 1M string widths: ~30 s with `NSString.size(withAttributes:)`, ~7 s with `NSLayoutManager` (>1 GB), Core Text framesetter ~2× faster parallelized (SO 30537811). Never measure the whole column; sample and clamp; use `CTLineGetTypographicBounds` for single lines.
- `NSTextField`: 1,500 fields took ~77 ms to render (forum 795048). SwiftUI `Text` cost is undocumented; treat it as one layout per body evaluation.
- TextKit 2 is viewport-based with estimated document height, relevant only for editable multi-line cells (krzyzanowski).
- `monospacedDigit()` affects digits only and requires font support; truncate once via `CTLineCreateTruncatedLine` on width change only.

## 4. Diffing and updates
- WWDC25 306: every row reading `model.isFavorite(item)` created a dependency on the whole array, so one change re-ran every visible body; fix is a per-item `@Observable` view-model held in an `@ObservationIgnored` dictionary. Frequently changing values in `Environment` notify every reader.
- WWDC23 10160: narrow view inputs, extract subviews, `Self._printChanges()` is debug-only; filter in the model, not in `ForEach`; avoid `id` modifier on List rows.
- `EquatableView`/`.equatable()`: default comparison is reflection-based and any closure property makes the view non-diffable (Airbnb).
- Diff cost at 100k elements (DifferenceKit's 2019 benchmark): DifferenceKit 0.035 s, IGListKit 0.70 s, `Swift.CollectionDifference` 5.03 s. At 1M rows, do not diff rows for rendering; the renderer reads a `(row, column)` cell on demand; diff only to animate small changes.
- `OrderedDictionary` = `OrderedSet` of keys + `Array` of values, O(1) lookup, positional access via `.elements`.

## 5. Scroll performance mechanics
- Budget: 8.3 ms/frame at 120Hz, ~5 ms after system overhead; target hitch ratio ≤5 ms/s; ≥10 ms/s is distracting (WWDC20 10077).
- ProMotion: iPhone needs `CADisableMinimumFrameDurationOnPhone` to exceed 60Hz. On the 2021 MacBook Pro most AppKit apps did not scroll at 120Hz while Catalyst and Metal apps did; Apple published no macOS guidance (9to5mac). `NSView.displayLink(target:selector:)` exists from macOS 14. Verify actual refresh with the Animation Hitches template.
- macOS `NSScrollView`: developers on Sonoma report `draw(_:)` called with `dirtyRect == visibleRect` every scroll step and `prepareContent(in:)` ignored, i.e., responsive-scrolling overdraw appears inactive (forum 740214). Overriding `scrollWheel(with:)` opts out of responsive scrolling unless `isCompatibleWithResponsiveScrolling` is true. Design for full-viewport redraw per frame. `canDrawConcurrently = true` lets AppKit draw off main thread when the window's `allowsConcurrentViewDrawing` is true. Giant layer-backed document views get an implicit `CATiledLayer` with seam reports; keep the drawn view viewport-sized and move its frame (forums 663536, 651229).
- Sticky headers/frozen columns: AppKit sync via `NSClipView.postsBoundsChangedNotifications` + `boundsDidChangeNotification`, apply offset synchronously (Tietze; Apple SynchroScroll). Headers driven from `didLiveScroll` tremble (forum 110167). In pure SwiftUI, syncing two `ScrollView`s lags a frame (forums 675431, 697329); the robust approach is one scroll surface drawing the frozen header/column at offset-adjusted positions in the same pass. `LazyVStack(pinnedViews:)` has bounce-loop and overlap reports (forums 777667, 820278).

## 6. Column layout algorithms
`NSTableView.ColumnAutoresizingStyle` defines the reference semantics: `uniform`, `sequential`, `reverseSequential`, `lastColumnOnly`, `firstColumnOnly`, `none`; per-column `minWidth`/`maxWidth`, `resizingMask`. Implement in the headless core as: resolve `fixed`/`flex(weight)`/`fill` → clamp to min/max → redistribute remainder iteratively → persist widths and order keyed by column ID. Auto-size to content by sampling, never by full-column measurement.

## 7. Measurement methodology
- Instruments 26 SwiftUI instrument: Update Groups lane, Long View Body / Long Representable / Other Long Updates, Cause & Effect graph (WWDC25 306).
- Animation Hitches template + VSync track; compare frame intervals to 8.33 ms.
- XCTest: `measure(metrics: [XCTOSSignpostMetric.scrollDecelerationMetric])` (also `scrollDraggingMetric`, `scrollingAndDecelerationMetric`) reports hitch count, duration, ratio, frame rate; these hook UIKit scroll signposts, so on macOS emit your own `os_signpost` intervals around deceleration.
- Track body counts with `Self._printChanges()` in debug only; memory high-water via Allocations at launch, after scrolling to end, after return.

## 8. Prior art: headless core + renderers
No Swift port of TanStack Table exists. Closest Swift items: FastList (NSTableView-backed `List` replacement, macOS 13+, `rowContentID`); Nil Coalescing's pooled-row `Layout` recipe; Spark-Grid (WIP custom AppKit grid under a SwiftUI shell); vger's Metal glyph cache if you ever go GPU.

## Recommended architecture (macOS-first, iOS-capable, SwiftUI API, 1M rows at 120Hz)

Layer 1, headless core (pure Swift, platform-free, testable): `TableModel<Row>` holding a columnar or row-array data source accessed by index; column definitions (ID, width policy, min/max, formatter, alignment, pinned); sort/filter producing an index permutation (never copies rows); selection as `IndexSet`/ID set; a `Viewport` struct → visible row range via fixed row height or a Fenwick tree over heights with overscan; column prefix sums for horizontal virtualization; a `CellCache` keyed by `(rowIndex, columnID, dataVersion)` holding `CTLine`/width; width resolution; persisted layout state. Invalidation API is `invalidate(rows:)`/`invalidateAll()`, not a full diff.

Layer 2, renderers behind one protocol:
- Primary (macOS and iOS): a single custom `NSView`/`UIView` document view inside a native scroll view, frame = viewport, content size reported to the scroll view, drawing only `visibleRange × visibleColumns` with cached `CTLine`s in `draw(_:)`; layer-backed; `canDrawConcurrently`; frozen header and pinned columns drawn in the same pass; selection, hover, focus ring and sort indicators drawn natively; accessibility via a synthesized element grid for visible cells plus counts.
- Secondary (fidelity mode, modest data): pooled SwiftUI rows via `onScrollGeometryChange` + custom `Layout` (macOS 15/iOS 18+) for rich interactive cells.
- Compatibility (iOS small data): `UICollectionView` with compositional layout and cell registration.

Layer 3, SwiftUI API: a struct whose body picks the renderer by platform/data size, exposes `selection`, `sortOrder`, `columnWidths` bindings, and keeps `@Observable` dependencies per cell view-model so a one-cell change invalidates one draw rect.

Why not the alternatives: SwiftUI `Table` is NSTableView-backed but its identity/diff machinery hangs at 1k–5k rows on updates/selection and has no column virtualization. Plain `NSTableView` with `NSTextField` cells is a solid fallback to ~20 columns, but 50 columns × 60 visible rows = 3,000 live views and no column virtualization. `LazyVStack` cannot report true content size at 1M rows.

Risks: (1) owning selection/keyboard/VoiceOver semantics; mitigate with the `NSTableView` renderer as a correctness oracle. (2) Full-viewport redraw per frame on macOS: keep per-frame draw under ~4 ms at 50 × 60; fall back to per-row `CALayer` tiles if needed. (3) 120Hz on macOS not guaranteed by AppKit; validate with the hitch instrument. (4) Variable heights jiggle the scrollbar; fixed by default, opt-in variable with background measurement. (5) Pooled-row renderer depends on macOS 15/iOS 18 and manual `@State` resets. (6) Auto-size by sampling only. (7) Columnar store with lazy formatting into the cache and a bounded LRU. (8) Re-benchmark SwiftUI `Table` each major release.
