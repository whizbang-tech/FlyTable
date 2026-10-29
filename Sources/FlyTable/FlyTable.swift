import SwiftUI
import FlyTableCore
#if os(macOS)
import AppKit
#endif

/// A table with a SwiftUI API over a custom-drawn native renderer. Sorting is applied by the
/// table as an index permutation; selection, sort order and column layout are host-owned bindings.
///
/// ```swift
/// FlyTable(matters, selection: $selection, sortOrder: $sort) {
///   FlyColumn("Matter", value: \.title).pinned().width(.flex(2))
///   FlyColumn("Client", value: \.client)
///   FlyColumn("Hours", value: \.hours)
/// }
/// .tableStyle(.inset)
/// .density(.comfortable)
/// ```
public struct FlyTable<Row: Identifiable>: View where Row.ID: Hashable & Sendable {
  private let rows: [Row]
  private let revision: Int
  private let columns: [FlyColumn<Row>]
  @Binding private var selection: Set<Row.ID>
  @Binding private var sortOrder: FlySortOrder
  private var layout: Binding<FlyColumnLayoutState>?
  private var style: FlyTableStyle = .inset
  private var density: FlyRowDensity = .comfortable
  private var alternatingRows = false
  private var rowSeparators = false
  private var columnSeparators = false
  private var onActivate: ((Set<Row.ID>) -> Void)?
  private var contextMenu: ((Set<Row.ID>) -> [FlyMenuItem])?

  /// `revision` tells the table that row values changed without the array identity changing;
  /// bump it to re-sort. The count changing always re-sorts.
  public init(
    _ rows: [Row], revision: Int = 0, selection: Binding<Set<Row.ID>>, sortOrder: Binding<FlySortOrder>,
    layout: Binding<FlyColumnLayoutState>? = nil, @FlyColumnBuilder columns: () -> [FlyColumn<Row>]
  ) {
    self.rows = rows
    self.revision = revision
    self.columns = columns()
    _selection = selection
    _sortOrder = sortOrder
    self.layout = layout
  }

  public func tableStyle(_ style: FlyTableStyle) -> Self { var c = self; c.style = style; return c }
  public func density(_ density: FlyRowDensity) -> Self { var c = self; c.density = density; return c }
  public func alternatingRowBackgrounds(_ on: Bool = true) -> Self { var c = self; c.alternatingRows = on; return c }
  public func rowSeparators(_ on: Bool = true) -> Self { var c = self; c.rowSeparators = on; return c }
  public func columnSeparators(_ on: Bool = true) -> Self { var c = self; c.columnSeparators = on; return c }
  /// Double-click or Return on the selection.
  public func onRowActivate(_ action: @escaping (Set<Row.ID>) -> Void) -> Self { var c = self; c.onActivate = action; return c }
  /// Right-click selects the row under the pointer first, then asks for items for the selection.
  public func contextMenu(_ items: @escaping (Set<Row.ID>) -> [FlyMenuItem]) -> Self { var c = self; c.contextMenu = items; return c }

  public var body: some View {
    #if os(macOS)
    FlyTableRepresentable(table: self)
    #else
    Text("FlyTable: the iOS renderer is scheduled (see docs/proposal.md §5.5).")
    #endif
  }

  #if os(macOS)
  fileprivate struct FlyTableRepresentable: NSViewRepresentable {
    let table: FlyTable<Row>

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> FlyTableScrollView {
      let scrollView = FlyTableScrollView(frame: .zero)
      let view = FlyTableDocumentView(engine: context.coordinator.engine)
      scrollView.documentView = view
      context.coordinator.view = view
      wire(view, context: context)
      apply(to: view, coordinator: context.coordinator, initial: true)
      return scrollView
    }

    func updateNSView(_ scrollView: FlyTableScrollView, context: Context) {
      guard let view = context.coordinator.view else { return }
      wire(view, context: context)
      apply(to: view, coordinator: context.coordinator, initial: false)
    }

    private func wire(_ view: FlyTableDocumentView<Row>, context: Context) {
      let selection = table._selection
      let sort = table._sortOrder
      let layout = table.layout
      view.onSelectionChange = { selection.wrappedValue = $0.ids }
      view.onSortChange = { sort.wrappedValue = $0 }
      view.onLayoutChange = { layout?.wrappedValue = $0 }
      view.onActivate = table.onActivate
      view.contextMenu = table.contextMenu
    }

    private func apply(to view: FlyTableDocumentView<Row>, coordinator: Coordinator, initial: Bool) {
      let engine = coordinator.engine
      var needsLayout = initial
      engine.setColumns(table.columns)
      if initial || table.rows.count != engine.rows.count || table.revision != engine.revision {
        engine.setRows(table.rows, revision: table.revision)
        needsLayout = true
      }
      if engine.sortOrder != table.sortOrder { engine.sortOrder = table.sortOrder; needsLayout = true }
      if let layout = table.layout?.wrappedValue, layout != engine.layout { engine.layout = layout; needsLayout = true }
      if engine.selection.ids != table.selection {
        engine.selection.ids = table.selection
        view.setNeedsDisplay(view.visibleRect)
      }
      var configuration = view.configuration
      configuration.style = table.style
      configuration.density = table.density
      configuration.alternatingRows = table.alternatingRows
      configuration.rowSeparators = table.rowSeparators
      configuration.columnSeparators = table.columnSeparators
      if configuration.style != view.configuration.style || configuration.density != view.configuration.density
        || configuration.alternatingRows != view.configuration.alternatingRows
        || configuration.rowSeparators != view.configuration.rowSeparators
        || configuration.columnSeparators != view.configuration.columnSeparators {
        view.configuration = configuration  // triggers invalidateAll
        needsLayout = false
      }
      if needsLayout { view.invalidateAll() }
    }

    @MainActor final class Coordinator {
      let engine = FlyTableEngine<Row>()
      var view: FlyTableDocumentView<Row>?
    }
  }
  #endif
}
