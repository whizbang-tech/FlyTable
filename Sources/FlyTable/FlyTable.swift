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
  private var selectionMode: FlySelectionMode = .multiple
  private var disabledIDs: Set<Row.ID> = []
  private var sortsRows = true
  private var selectsOnClick = true
  private var togglesSoleSelection = false
  private var togglesSelection = false
  private var focusedActivationOnly = false
  private var refreshRows = false
  private var fixedRowHeight: CGFloat?
  private var fixedHeaderHeight: CGFloat?
  private var keyboardNavigation = true
  private var multiColumnSorting = true
  private var rowHeightProvider: ((Row) -> CGFloat?)?
  private var rowContentProvider: ((Row) -> AnyView?)?
  private var showsHeader = true
  private var focusedRowID: Binding<Row.ID?>?
  private var selectionChanged: ((Set<Row.ID>) -> Void)?
  private var rowClicked: ((Row.ID) -> Void)?
  private var openInNewTab: ((Set<Row.ID>) -> Void)?
  private var focusChanged: ((Row.ID?) -> Void)?
  private var scrollEndVisible: (() -> Void)?
  #if os(macOS)
  private var dragSource: ((Set<Row.ID>) -> [NSPasteboardWriting])?
  private var dropTypes: [NSPasteboard.PasteboardType] = []
  private var validateDrop: ((NSDraggingInfo, Row.ID?) -> NSDragOperation)?
  private var performDrop: ((NSDraggingInfo, Row.ID?) -> Bool)?
  #endif
  private var scrollChanged: ((CGRect, CGSize) -> Void)?
  private var style: FlyTableStyle = .inset
  private var density: FlyRowDensity = .comfortable
  private var alternatingRows = false
  private var rowSeparators = false
  private var columnSeparators = false
  #if os(macOS)
  private var theme: FlyTableTheme = .system
  #endif
  private var onActivate: ((Set<Row.ID>) -> Void)?
  private var firstResponderChanged: ((Bool) -> Void)?
  private var rowMenu: ((Row.ID, Set<Row.ID>) -> [FlyMenuItem])?
  private var columnMenu: ((FlyColumnID) -> [FlyMenuItem])?
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

  public func selectionMode(_ mode: FlySelectionMode) -> Self { var c = self; c.selectionMode = mode; return c }
  public func disabledRowIDs(_ ids: Set<Row.ID>) -> Self { var c = self; c.disabledIDs = ids; return c }
  public func activatesFocusedRowOnly(_ enabled: Bool = true) -> Self { var c = self; c.focusedActivationOnly = enabled; return c }
  public func selectsOnRowClick(_ enabled: Bool) -> Self { var c = self; c.selectsOnClick = enabled; return c }
  public func togglesSoleSelectionOnClick(_ enabled: Bool = true) -> Self { var c = self; c.togglesSoleSelection = enabled; return c }
  public func togglesSelectionOnClick(_ enabled: Bool = true) -> Self { var c = self; c.togglesSelection = enabled; return c }
  public func sortsRows(_ enabled: Bool) -> Self { var c = self; c.sortsRows = enabled; return c }
  public func refreshRowsOnUpdate(_ enabled: Bool = true) -> Self { var c = self; c.refreshRows = enabled; return c }
  public func headerHeight(_ height: CGFloat?) -> Self { var c = self; c.fixedHeaderHeight = height.map { max($0, 1) }; return c }
  public func keyboardNavigationEnabled(_ enabled: Bool) -> Self { var c = self; c.keyboardNavigation = enabled; return c }
  public func allowsMultiColumnSorting(_ enabled: Bool) -> Self { var c = self; c.multiColumnSorting = enabled; return c }
  public func rowHeight(_ height: CGFloat) -> Self { var c = self; c.fixedRowHeight = max(height, 1); return c }
  public func rowHeight(_ height: @escaping (Row) -> CGFloat?) -> Self { var c = self; c.rowHeightProvider = height; return c }
  public func rowContent(_ content: @escaping (Row) -> AnyView?) -> Self { var c = self; c.rowContentProvider = content; return c }
  public func showsHeader(_ visible: Bool) -> Self { var c = self; c.showsHeader = visible; return c }
  public func focusedRow(_ id: Binding<Row.ID?>?) -> Self { var c = self; c.focusedRowID = id; return c }
  public func onSelectionChange(_ action: @escaping (Set<Row.ID>) -> Void) -> Self { var c = self; c.selectionChanged = action; return c }
  public func onRowClick(_ action: @escaping (Row.ID) -> Void) -> Self { var c = self; c.rowClicked = action; return c }
  public func onRowOpenInNewTab(_ action: ((Set<Row.ID>) -> Void)?) -> Self { var c = self; c.openInNewTab = action; return c }
  public func onScrollGeometryChange(_ action: @escaping (CGRect, CGSize) -> Void) -> Self { var c = self; c.scrollChanged = action; return c }

  public func onFocusChange(_ action: @escaping (Row.ID?) -> Void) -> Self { var c = self; c.focusChanged = action; return c }
  public func onScrollEndVisible(_ action: @escaping () -> Void) -> Self { var c = self; c.scrollEndVisible = action; return c }
  #if os(macOS)
  public func onDragRows(_ action: @escaping (Set<Row.ID>) -> [NSPasteboardWriting]) -> Self { var c = self; c.dragSource = action; return c }
  public func onDropRows(types: [NSPasteboard.PasteboardType], validate: @escaping (NSDraggingInfo, Row.ID?) -> NSDragOperation, perform: @escaping (NSDraggingInfo, Row.ID?) -> Bool) -> Self {
    var c = self; c.dropTypes = types; c.validateDrop = validate; c.performDrop = perform; return c
  }
  #endif

  public func onFirstResponderChange(_ action: @escaping (Bool) -> Void) -> Self { var c = self; c.firstResponderChanged = action; return c }
  public func columnContextMenu(_ items: @escaping (FlyColumnID) -> [FlyMenuItem]) -> Self { var c = self; c.columnMenu = items; return c }
  public func rowContextMenu(_ items: @escaping (Row.ID, Set<Row.ID>) -> [FlyMenuItem]) -> Self { var c = self; c.rowMenu = items; return c }
  public func tableStyle(_ style: FlyTableStyle) -> Self { var c = self; c.style = style; return c }
  public func density(_ density: FlyRowDensity) -> Self { var c = self; c.density = density; return c }
  public func alternatingRowBackgrounds(_ on: Bool = true) -> Self { var c = self; c.alternatingRows = on; return c }
  public func rowSeparators(_ on: Bool = true) -> Self { var c = self; c.rowSeparators = on; return c }
  public func columnSeparators(_ on: Bool = true) -> Self { var c = self; c.columnSeparators = on; return c }
  #if os(macOS)
  /// Colours and fonts; `.system` (Finder, Mail) or `.flyUI` (FlyUI's default table).
  public func theme(_ theme: FlyTableTheme) -> Self { var c = self; c.theme = theme; return c }
  #endif
  /// Double-click or Return on the selection.
  public func onRowActivate(_ action: @escaping (Set<Row.ID>) -> Void) -> Self { var c = self; c.onActivate = action; return c }
  /// Right-click selects the row under the pointer first, then asks for items for the selection.
  public func contextMenu(_ items: @escaping (Set<Row.ID>) -> [FlyMenuItem]) -> Self { var c = self; c.contextMenu = items; return c }

  public var body: some View {
    #if os(macOS)
    if style == .card {
      FlyTableRepresentable(table: self)
        .clipShape(RoundedRectangle(cornerRadius: theme.cardCornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: theme.cardCornerRadius, style: .continuous).strokeBorder(Color(nsColor: theme.cardBorder), lineWidth: 1))
    } else {
      FlyTableRepresentable(table: self)
    }
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
      view.onSelectionChange = {
        selection.wrappedValue = $0.ids
        table.focusedRowID?.wrappedValue = $0.focused
        table.focusChanged?($0.focused)
        table.selectionChanged?($0.ids)
      }
      view.onRowClick = table.rowClicked
      view.onOpenInNewTab = table.openInNewTab
      view.onScrollChange = table.scrollChanged
      view.onScrollEndVisible = table.scrollEndVisible
      view.dragSource = table.dragSource
      view.validateDrop = table.validateDrop
      view.performDrop = table.performDrop
      view.registerForDraggedTypes(table.dropTypes)
      view.hostingEnvironment = context.environment
      view.onSortChange = { sort.wrappedValue = $0 }
      view.onLayoutChange = { layout?.wrappedValue = $0 }
      view.onActivate = table.onActivate
      view.contextMenu = table.contextMenu
      view.rowContextMenu = table.rowMenu
      view.columnContextMenu = table.columnMenu
      view.onFirstResponderChange = table.firstResponderChanged
    }

    private func apply(to view: FlyTableDocumentView<Row>, coordinator: Coordinator, initial: Bool) {
      let engine = coordinator.engine
      var needsLayout = initial
      engine.sortsRows = table.sortsRows
      view.isInteractionEnabled = view.hostingEnvironment.isEnabled
      view.focusedActivationOnly = table.focusedActivationOnly
      view.keyboardNavigationEnabled = table.keyboardNavigation
      view.allowsMultiColumnSorting = table.multiColumnSorting
      view.selectionMode = table.selectionMode
      view.selectsOnClick = table.selectsOnClick
      view.togglesSoleSelection = table.togglesSoleSelection
      view.togglesSelection = table.togglesSelection
      view.disabledIDs = table.disabledIDs
      view.rowHeightProvider = table.rowHeightProvider
      view.rowContentProvider = table.rowContentProvider
      engine.setColumns(table.columns)
      if initial || table.refreshRows || table.rows.count != engine.rows.count || table.revision != engine.revision {
        engine.setRows(table.rows, revision: table.revision)
        needsLayout = true
      }
      if engine.sortOrder != table.sortOrder { engine.sortOrder = table.sortOrder; needsLayout = true }
      if let layout = table.layout?.wrappedValue, layout != engine.layout { engine.layout = layout; needsLayout = true }
      if engine.selection.ids != table.selection {
        engine.selection.ids = table.selection
        view.setNeedsDisplay(view.visibleRect)
      }
      if let binding = table.focusedRowID, binding.wrappedValue != engine.selection.focused {
        engine.selection.focused = binding.wrappedValue
        if let id = binding.wrappedValue, let index = engine.displayIndex(of: id) { view.scrollToRow(index) }
      }
      var configuration = view.configuration
      configuration.rowHeight = table.fixedRowHeight
      configuration.headerHeight = table.fixedHeaderHeight
      configuration.showsHeader = table.showsHeader
      configuration.style = table.style
      configuration.density = table.density
      configuration.alternatingRows = table.alternatingRows
      configuration.rowSeparators = table.rowSeparators
      configuration.columnSeparators = table.columnSeparators
      configuration.theme = table.theme
      let themeChanged = configuration.theme.cellFont != view.configuration.theme.cellFont || configuration.theme.background != view.configuration.theme.background
      if configuration.headerHeight != view.configuration.headerHeight || configuration.rowHeight != view.configuration.rowHeight || configuration.showsHeader != view.configuration.showsHeader || themeChanged || configuration.style != view.configuration.style || configuration.density != view.configuration.density
        || configuration.alternatingRows != view.configuration.alternatingRows
        || configuration.rowSeparators != view.configuration.rowSeparators
        || configuration.columnSeparators != view.configuration.columnSeparators {
        view.configuration = configuration  // triggers invalidateAll
        needsLayout = false
      }
      if needsLayout { view.invalidateAll() }
      view.updateHostedContent()
    }

    @MainActor final class Coordinator {
      let engine = FlyTableEngine<Row>()
      var view: FlyTableDocumentView<Row>?
    }
  }
  #endif
}

/// A disambiguated spelling for adapters that already expose their own `FlyTable` type.
public typealias FlyRenderedTable<Row: Identifiable> = FlyTable<Row> where Row.ID: Hashable & Sendable
