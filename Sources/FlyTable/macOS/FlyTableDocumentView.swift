#if os(macOS)
import AppKit
import CoreText
import SwiftUI
import FlyTableCore

/// The custom-drawn table body. One view, sized to the whole content, draws only the visible
/// rows × visible columns from cached Core Text lines, with the floating header and pinned
/// columns painted in the same pass. Cost per frame is O(visible cells).
@MainActor
final class FlyTableDocumentView<Row: Identifiable>: NSView, NSDraggingSource where Row.ID: Hashable & Sendable {
  let engine: FlyTableEngine<Row>
  var configuration = FlyTableConfiguration() { didSet { invalidateAll() } }

  var onSelectionChange: ((FlySelection<Row.ID>) -> Void)?
  var onSortChange: ((FlySortOrder) -> Void)?
  var onLayoutChange: ((FlyColumnLayoutState) -> Void)?
  var onActivate: ((Set<Row.ID>) -> Void)?
  var selectsOnClick = true
  var togglesSoleSelection = false
  var togglesSelection = false
  var focusedActivationOnly = false
  var isInteractionEnabled = true
  var keyboardNavigationEnabled = true
  var allowsMultiColumnSorting = true
  var selectionMode: FlySelectionMode = .multiple
  var disabledIDs: Set<Row.ID> = []
  var onRowClick: ((Row.ID) -> Void)?
  var onOpenInNewTab: ((Set<Row.ID>) -> Void)?
  var dragSource: ((Set<Row.ID>) -> [NSPasteboardWriting])?
  var validateDrop: ((NSDraggingInfo, Row.ID?) -> NSDragOperation)?
  var performDrop: ((NSDraggingInfo, Row.ID?) -> Bool)?
  var onScrollEndVisible: (() -> Void)?
  private var lastScrollEnd: (Bool, CGFloat)?
  private var lastScrollGeometry: (CGRect, CGSize)?
  private var dragStart: NSPoint?
  private var draggingRows = false
  var onScrollChange: ((CGRect, CGSize) -> Void)?
  var rowHeightProvider: ((Row) -> CGFloat?)?
  var rowContentProvider: ((Row) -> AnyView?)?
  var hostingEnvironment = EnvironmentValues()
  private struct HostedKey: Hashable { let row: Row.ID?; let column: FlyColumnID? }
  private var measuredRowHeights: [Row.ID: CGFloat] = [:]
  private var measurementLayoutPending = false
  private var accessibleRows: [Row.ID: FlyTableAccessibilityElement] = [:]
  private var accessibleCells: [HostedKey: FlyTableAccessibilityElement] = [:]
  private var hosted: [HostedKey: FlyHostedCell] = [:]
  var onFirstResponderChange: ((Bool) -> Void)?
  var columnContextMenu: ((FlyColumnID) -> [FlyMenuItem])?
  var rowContextMenu: ((Row.ID, Set<Row.ID>) -> [FlyMenuItem])?
  var contextMenu: ((Set<Row.ID>) -> [FlyMenuItem])?

  private(set) var resolved: [FlyResolvedColumn] = []
  private var geometry = FlyRowGeometry(rowCount: 0, rowHeight: 28)
  private let lines = FlyCellCache<FlyRenderedCell>(capacity: 30_000)
  private var fitWidths: [FlyColumnID: CGFloat] = [:]
  private var fitRevision = -1
  private var hoveredRow: Int?
  private var isWindowKey = true
  private var resize: (column: FlyColumnID, startX: CGFloat, startWidth: CGFloat)?
  private var headerDragStart: NSPoint?
  private var reorderedHeader = false
  private var headerPress: (column: FlyColumnID, additive: Bool)?
  private var menuProxies: [FlyMenuProxy] = []
  private var trackingArea: NSTrackingArea?
  private var lastClipWidth: CGFloat = 0

  init(engine: FlyTableEngine<Row>) {
    self.engine = engine
    super.init(frame: .zero)
    wantsLayer = false
    canDrawConcurrently = true
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var isFlipped: Bool { true }
  override var acceptsFirstResponder: Bool { true }
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
  override var isOpaque: Bool { configuration.style != .plain }

  var rowHeight: CGFloat { configuration.rowHeight ?? configuration.density.rowHeight }
  var headerHeight: CGFloat { configuration.showsHeader ? (configuration.headerHeight ?? configuration.density.rowHeight) : 0 }
  private var theme: FlyTableTheme { configuration.theme }
  private var horizontalMargin: CGFloat { configuration.style == .inset ? theme.insetStyleMargin : 0 }

  // MARK: Layout

  func relayout() {
    let clipWidth = enclosingScrollView?.contentView.bounds.width ?? bounds.width
    if rowHeightProvider != nil || rowContentProvider != nil || engine.columns.contains(where: { $0.cellContent != nil }) {
      geometry = FlyRowGeometry(heights: (0..<engine.count).map { max(rowHeightProvider?(engine.row(atDisplayIndex: $0)) ?? measuredRowHeights[engine.id(atDisplayIndex: $0)] ?? rowHeight, 1) }, defaultHeight: rowHeight)
    } else {
      geometry = FlyRowGeometry(rowCount: engine.count, rowHeight: rowHeight)
    }
    computeFitWidthsIfNeeded()
    let available = max(clipWidth - horizontalMargin * 2, 0)
    resolved = FlyColumnLayoutResolver.resolve(specs: engine.specs, state: engine.layout, availableWidth: available, fitWidths: fitWidths)
    let total = (resolved.last?.maxX ?? 0) + horizontalMargin * 2
    let height = headerHeight + geometry.contentHeight
    let newSize = NSSize(width: max(total, clipWidth), height: max(height, enclosingScrollView?.contentView.bounds.height ?? 0))
    if frame.size != newSize { setFrameSize(newSize) }
    lines.removeAll()
    needsDisplay = true
    updateHostedContent()
    reportScrollGeometry()
  }

  func invalidateAll() {
    lines.removeAll()
    relayout()
  }

  private func computeFitWidthsIfNeeded() {
    guard fitRevision != engine.revision else { return }
    fitRevision = engine.revision
    fitWidths = [:]
    let sample = min(engine.count, 300)
    let stride = max(engine.count / max(sample, 1), 1)
    for column in engine.columns where column.spec.width == .fit {
      var width: CGFloat = 0
      let font = column.spec.alignment == .numeric ? theme.numericFont : theme.cellFont
      for k in 0..<sample {
        let i = min(k * stride, engine.count - 1)
        let value = engine.value(atDisplayIndex: i, column: column.spec.id)
        let s = value.displayString()
        var w = (s as NSString).size(withAttributes: [.font: font]).width
        if case .badge = value { w = (s as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 12)]).width + 16 }
        width = max(width, w)
      }
      let title = (column.spec.title as NSString).size(withAttributes: [.font: theme.headerFont]).width + 18
      fitWidths[column.spec.id] = ceil(max(width, title)) + theme.cellInset * 2
    }
  }

  private var visibleArea: NSRect { enclosingScrollView?.documentVisibleRect ?? bounds }

  func rowRect(_ displayIndex: Int) -> NSRect {
    NSRect(x: 0, y: headerHeight + geometry.minY(ofRow: displayIndex), width: bounds.width, height: geometry.height(ofRow: displayIndex))
  }

  private func displayIndex(at point: NSPoint) -> Int? {
    let y = point.y - headerHeight
    guard y >= 0, y < geometry.contentHeight, engine.count > 0 else { return nil }
    return geometry.row(atY: y)
  }

  private func columnX(_ column: FlyResolvedColumn) -> CGFloat { horizontalMargin + column.x }

  private var pinnedWidth: CGFloat {
    resolved.filter { $0.spec.pin == .leading }.reduce(0) { $0 + $1.width }
  }

  /// Custom content is opt-in and materialized only for cells intersecting the viewport.
  /// Each host sits inside a clipping view so horizontal scrolling cannot cover pinned cells
  /// and vertical scrolling cannot cover the floating header.
  func updateHostedContent() {
    let visible = visibleArea
    guard visible.width > 0, visible.height > 0 else { return }
    let bodyVisible = CGRect(x: visible.minX, y: visible.minY + headerHeight, width: visible.width, height: max(visible.height - headerHeight, 0))
    var active: Set<HostedKey> = []
    func install(_ key: HostedKey, _ content: AnyView, frame: CGRect, clip: CGRect) {
      let intersection = frame.intersection(clip)
      guard !intersection.isNull, intersection.width > 0, intersection.height > 0 else { return }
      active.insert(key)
      let cell = hosted[key] ?? FlyHostedCell()
      if hosted[key] == nil { hosted[key] = cell; addSubview(cell) }
      cell.frame = intersection
      cell.host.frame = CGRect(x: frame.minX - intersection.minX, y: frame.minY - intersection.minY, width: frame.width, height: frame.height)
      cell.host.rootView = AnyView(content.environment(\.self, hostingEnvironment)
        .disabled(key.column != nil && (key.row.map { disabledIDs.contains($0) } ?? false)))
      cell.host.forwardMouseDown = { [weak self] event in self?.mouseDown(with: event) }
    }
    func recordHeight(_ height: CGFloat, for row: Row, current: CGFloat) {
      guard rowHeightProvider?(row) == nil else { return }
      let fitted = max(height.rounded(.up), rowHeight)
      guard fitted.isFinite, abs(fitted - current) > 0.5 else { return }
      measuredRowHeights[row.id] = fitted
      if !measurementLayoutPending {
        measurementLayoutPending = true
        DispatchQueue.main.async { [weak self] in
          guard let self else { return }
          self.measurementLayoutPending = false
          self.relayout()
        }
      }
    }
    for i in geometry.rows(in: (visible.minY - headerHeight)...(visible.maxY - headerHeight)) {
      let row = engine.row(atDisplayIndex: i)
      let rect = rowRect(i)
      if let content = rowContentProvider?(row) {
        let key = HostedKey(row: row.id, column: nil)
        install(key, content,
          frame: CGRect(x: visible.minX, y: rect.minY, width: visible.width, height: rect.height), clip: bodyVisible)
        if let host = hosted[key]?.host { recordHeight(host.fittingSize.height, for: row, current: rect.height) }
        continue
      }
      var fittedHeight: CGFloat = rowHeight
      var hasHostedCell = false
      for column in resolved {
        guard let content = engine.columns.first(where: { $0.spec.id == column.id })?.cellContent?(row) else { continue }
        let isPinned = column.spec.pin == .leading
        let x = columnX(column) + (isPinned ? visible.minX : 0)
        var clip = bodyVisible
        if !isPinned { clip.origin.x += horizontalMargin + pinnedWidth; clip.size.width = max(clip.width - horizontalMargin - pinnedWidth, 0) }
        let key = HostedKey(row: row.id, column: column.id)
        install(key, content,
          frame: CGRect(x: x + theme.cellInset, y: rect.minY, width: max(column.width - 2 * theme.cellInset, 1), height: rect.height), clip: clip)
        if let host = hosted[key]?.host { hasHostedCell = true; fittedHeight = max(fittedHeight, host.fittingSize.height) }
      }
      if hasHostedCell { recordHeight(fittedHeight, for: row, current: rect.height) }
    }
    if configuration.showsHeader {
      for column in resolved {
        guard let content = engine.columns.first(where: { $0.spec.id == column.id })?.headerContent?() else { continue }
        let isPinned = column.spec.pin == .leading
        let x = columnX(column) + (isPinned ? visible.minX : 0)
        var clip = CGRect(x: visible.minX, y: visible.minY, width: visible.width, height: headerHeight)
        if !isPinned { clip.origin.x += horizontalMargin + pinnedWidth; clip.size.width = max(clip.width - horizontalMargin - pinnedWidth, 0) }
        install(HostedKey(row: nil, column: column.id), content,
          frame: CGRect(x: x + theme.cellInset, y: visible.minY, width: max(column.width - 2 * theme.cellInset, 1), height: headerHeight), clip: clip)
      }
    }
    for key in Array(hosted.keys) where !active.contains(key) { hosted.removeValue(forKey: key)?.removeFromSuperview() }
  }

  // MARK: Drawing

  override func draw(_ dirtyRect: NSRect) {
    guard let context = NSGraphicsContext.current?.cgContext else { return }
    let visible = visibleArea
    if configuration.style != .plain {
      theme.background.setFill()
      dirtyRect.fill()
    }
    guard !resolved.isEmpty else { return }

    let bodyRange = (dirtyRect.minY - headerHeight)...(dirtyRect.maxY - headerHeight)
    let rows = geometry.rows(in: bodyRange)
    let pinned = resolved.filter { $0.spec.pin == .leading }
    let scrollX = visible.minX
    let unpinned = FlyColumnLayoutResolver.visibleColumns(
      resolved.filter { $0.spec.pin != .leading },
      in: (dirtyRect.minX - horizontalMargin)...(dirtyRect.maxX - horizontalMargin))

    drawRowBackgrounds(rows, visible: visible)
    context.saveGState()
    if !pinned.isEmpty {
      context.clip(to: CGRect(x: scrollX + horizontalMargin + pinnedWidth, y: dirtyRect.minY, width: dirtyRect.width, height: dirtyRect.height))
    }
    for column in unpinned { drawCells(column, rows: rows, xOffset: 0, context: context) }
    context.restoreGState()
    if !pinned.isEmpty {
      let pinRect = NSRect(x: scrollX + horizontalMargin, y: dirtyRect.minY, width: pinnedWidth, height: dirtyRect.height)
      if configuration.style != .plain {
        theme.background.setFill()
        pinRect.fill()
      }
      drawRowBackgrounds(rows, visible: visible, clip: pinRect)
      for column in pinned { drawCells(column, rows: rows, xOffset: scrollX, context: context) }
      if scrollX > 0 {
        theme.separator.setFill()
        NSRect(x: pinRect.maxX - 0.5, y: dirtyRect.minY, width: 0.5, height: dirtyRect.height).fill()
      }
    }
    drawSeparators(rows, unpinned: unpinned, visible: visible)
    drawHeader(visible: visible, pinned: pinned, unpinned: unpinned, context: context)
  }

  private func drawRowBackgrounds(_ rows: Range<Int>, visible: NSRect, clip: NSRect? = nil) {
    let emphasized = isWindowKey && window?.firstResponder === self
    NSGraphicsContext.current?.saveGraphicsState()
    defer { NSGraphicsContext.current?.restoreGraphicsState() }
    if let clip { NSBezierPath(rect: clip).addClip() }
    for i in rows {
      var r = rowRect(i)
      r.origin.x = visible.minX
      r.size.width = visible.width
      if configuration.alternatingRows, i % 2 == 1 {
        theme.alternateRowBackground.setFill()
        r.fill()
      }
      let id = engine.id(atDisplayIndex: i)
      if engine.selection.ids.contains(id) {
        (emphasized ? theme.selectionEmphasized : theme.selectionUnemphasized).setFill()
        selectionPath(r, visible: visible).fill()
        if emphasized, let edge = theme.selectionEdge {
          edge.setStroke()
          let path = selectionPath(r.insetBy(dx: 0.5, dy: 0.5), visible: visible)
          path.lineWidth = 1
          path.stroke()
        }
      } else if hoveredRow == i {
        theme.hover.setFill()
        selectionPath(r, visible: visible).fill()
      }
    }
  }

  private func selectionPath(_ rowRect: NSRect, visible: NSRect) -> NSBezierPath {
    guard configuration.style == .inset else { return NSBezierPath(rect: rowRect) }
    var r = rowRect
    r.origin.x = max(rowRect.minX, visible.minX + horizontalMargin)
    r.size.width = min(rowRect.maxX, visible.maxX - horizontalMargin) - r.origin.x
    return NSBezierPath(roundedRect: r, xRadius: theme.selectionCornerRadius, yRadius: theme.selectionCornerRadius)
  }

  private func drawCells(_ column: FlyResolvedColumn, rows: Range<Int>, xOffset: CGFloat, context: CGContext) {
    guard engine.columns.first(where: { $0.spec.id == column.id })?.cellContent == nil else { return }
    let emphasized = isWindowKey && window?.firstResponder === self
    let inset = theme.cellInset
    let x = columnX(column) + xOffset
    let textWidth = max(column.width - inset * 2, 1)
    let font = column.spec.alignment == .numeric ? theme.numericFont : theme.cellFont
    context.saveGState()
    context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
    for i in rows {
      if rowContentProvider?(engine.row(atDisplayIndex: i)) != nil { continue }
      let key = FlyCellKey(row: i, column: column.id, revision: engine.revision)
      let cell = lines.value(for: key) { render(engine.value(atDisplayIndex: i, column: column.id), font: font, width: textWidth) }
      context.setAlpha(disabledIDs.contains(engine.id(atDisplayIndex: i)) ? 0.5 : 1)
      let selected = engine.selection.ids.contains(engine.id(atDisplayIndex: i))
      let r = rowRect(i)
      switch cell {
      case .line(let line):
        context.setFillColor((selected && emphasized ? theme.selectedText : theme.text).cgColor)
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        let baseline = (r.midY + (ascent - descent) / 2).rounded()
        let tx: CGFloat
        switch column.spec.alignment {
        case .leading: tx = x + inset
        case .center: tx = x + (column.width - width) / 2
        case .trailing, .numeric: tx = x + column.width - inset - width
        }
        context.textPosition = CGPoint(x: tx.rounded(), y: baseline)
        CTLineDraw(line, context)
      case .badges(let badges):
        drawBadges(badges, in: NSRect(x: x + inset, y: r.minY, width: textWidth, height: r.height), alignment: column.spec.alignment, context: context)
      }
    }
    context.restoreGState()
  }

  private func render(_ value: FlyCellValue, font: NSFont, width: CGFloat) -> FlyRenderedCell {
    switch value {
    case .badge(let b): return .badges([renderBadge(b)])
    case .badges(let bs): return .badges(bs.map(renderBadge))
    default: return .line(makeLine(value.displayString(), font: font, width: width))
    }
  }

  private var badgeFont: NSFont { .systemFont(ofSize: 12) }
  private func renderBadge(_ badge: FlyBadge) -> FlyRenderedBadge {
    let line = makeLine(badge.text, font: badgeFont, width: 240)
    let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    let symbol = badge.symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 10, weight: .semibold)) }
    return FlyRenderedBadge(line: line, textWidth: width, symbol: symbol, tint: badge.tint, fill: badge.fill)
  }

  /// FlyUI's capsules: 8pt horizontal padding, caption text, a wash with a 1pt edge (tinted), a
  /// solid hue with white text (solid), or the wash alone (quiet). Badges that do not fit collapse
  /// into a "+N" tail.
  private func drawBadges(_ badges: [FlyRenderedBadge], in rect: NSRect, alignment: FlyColumnAlignment, context: CGContext) {
    guard !badges.isEmpty else { return }
    let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    let height = min(rect.height - 6, 22).rounded()
    let gap: CGFloat = 6
    let pad: CGFloat = 8
    func width(_ b: FlyRenderedBadge) -> CGFloat { (b.textWidth + pad * 2 + (b.symbol == nil ? 0 : 14)).rounded() }
    var widths = badges.map(width)
    var shown = badges.count
    var total = widths.reduce(0, +) + gap * CGFloat(max(badges.count - 1, 0))
    var tail: FlyRenderedBadge?
    if total > rect.width, badges.count > 1 {
      shown = 0
      total = 0
      for w in widths {
        let tailWidth: CGFloat = 36
        if total + w + (shown > 0 ? gap : 0) + gap + tailWidth <= rect.width { total += w + (shown > 0 ? gap : 0); shown += 1 } else { break }
      }
      shown = max(shown, 1)
      let rest = badges.count - shown
      if rest > 0 {
        tail = renderBadge(FlyBadge("+\(rest)", tint: .neutral, fill: .quiet))
        widths = Array(widths.prefix(shown)) + [width(tail!)]
        total = widths.reduce(0, +) + gap * CGFloat(widths.count - 1)
      }
    }
    var cx: CGFloat
    switch alignment {
    case .leading: cx = rect.minX
    case .center: cx = rect.minX + max((rect.width - total) / 2, 0)
    case .trailing, .numeric: cx = rect.maxX - min(total, rect.width)
    }
    cx = cx.rounded()
    let y = (rect.midY - height / 2).rounded()
    context.saveGState()
    context.clip(to: rect)
    let drawn = Array(badges.prefix(shown)) + (tail.map { [$0] } ?? [])
    for (index, b) in drawn.enumerated() {
      let w = min(widths[index], rect.width)
      let capsule = NSBezierPath(roundedRect: NSRect(x: cx, y: y, width: w, height: height), xRadius: height / 2, yRadius: height / 2)
      let solid = b.tint.solid, ink = b.tint.swatch
      let hue = NSColor(srgbRed: solid.red, green: solid.green, blue: solid.blue, alpha: 1)
      let inkColor = isDark ? hue.blended(withFraction: 0.35, of: .white) ?? hue : NSColor(srgbRed: ink.red, green: ink.green, blue: ink.blue, alpha: 1)
      switch b.fill {
      case .solid:
        hue.setFill(); capsule.fill()
      case .tinted:
        hue.withAlphaComponent(isDark ? 0.26 : 0.14).setFill(); capsule.fill()
        hue.withAlphaComponent(isDark ? 0.5 : 0.38).setStroke()
        let edge = NSBezierPath(roundedRect: NSRect(x: cx + 0.5, y: y + 0.5, width: w - 1, height: height - 1), xRadius: height / 2, yRadius: height / 2)
        edge.lineWidth = 1; edge.stroke()
      case .quiet:
        hue.withAlphaComponent(isDark ? 0.22 : 0.11).setFill(); capsule.fill()
      }
      let textColor: NSColor = b.fill == .solid ? .white : inkColor
      var tx = cx + pad
      if let symbol = b.symbol {
        symbol.withSymbolConfiguration(.init(paletteColors: [textColor]))?.draw(in: NSRect(x: tx, y: y + (height - 10) / 2, width: 11, height: 10))
        tx += 14
      }
      var ascent: CGFloat = 0, descent: CGFloat = 0
      _ = CTLineGetTypographicBounds(b.line, &ascent, &descent, nil)
      context.setFillColor(textColor.cgColor)
      context.textPosition = CGPoint(x: tx.rounded(), y: (y + height / 2 + (ascent - descent) / 2).rounded())
      CTLineDraw(b.line, context)
      cx += w + gap
    }
    context.restoreGState()
  }

  private func makeLine(_ string: String, font: NSFont, width: CGFloat) -> CTLine {
    let attributes: [NSAttributedString.Key: Any] = [
      .font: font, NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
    ]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attributes))
    if CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)) <= width { return line }
    let token = CTLineCreateWithAttributedString(NSAttributedString(string: "…", attributes: attributes))
    return CTLineCreateTruncatedLine(line, Double(width), .end, token) ?? line
  }

  private func drawSeparators(_ rows: Range<Int>, unpinned: ArraySlice<FlyResolvedColumn>, visible: NSRect) {
    theme.separator.setFill()
    if configuration.rowSeparators {
      for i in rows {
        let r = rowRect(i)
        NSRect(x: visible.minX + horizontalMargin, y: r.maxY - 0.5, width: visible.width - horizontalMargin * 2, height: 0.5).fill()
      }
    }
    if configuration.columnSeparators {
      for c in unpinned.dropLast() {
        NSRect(x: columnX(c) + c.width - 0.5, y: visible.minY + headerHeight, width: 0.5, height: visible.height - headerHeight).fill()
      }
    }
  }

  private func drawHeader(visible: NSRect, pinned: [FlyResolvedColumn], unpinned: ArraySlice<FlyResolvedColumn>, context: CGContext) {
    guard configuration.showsHeader else { return }
    let y = configuration.floatingHeader ? visible.minY : 0
    let headerRect = NSRect(x: visible.minX, y: y, width: visible.width, height: headerHeight)
    theme.headerBackground.setFill()
    headerRect.fill()
    theme.separator.setFill()
    NSRect(x: visible.minX + horizontalMargin, y: headerRect.maxY - 0.5, width: visible.width - horizontalMargin * 2, height: 0.5).fill()

    func drawTitle(_ column: FlyResolvedColumn, xOffset: CGFloat) {
      guard engine.columns.first(where: { $0.spec.id == column.id })?.headerContent == nil else { return }
      let x = columnX(column) + xOffset
      let inset = theme.cellInset
      let sort = engine.sortOrder.descriptor(for: column.id)
      let chevronWidth: CGFloat = sort == nil ? 0 : 14
      let attributes: [NSAttributedString.Key: Any] = [.font: theme.headerFont, .foregroundColor: theme.headerText]
      let title = NSAttributedString(string: column.spec.title, attributes: attributes)
      let size = title.size()
      let textWidth = max(column.width - inset * 2 - chevronWidth, 1)
      let shown = min(size.width, textWidth)
      let tx: CGFloat
      switch column.spec.alignment {
      case .leading: tx = x + inset
      case .center: tx = x + (column.width - shown) / 2
      case .trailing, .numeric: tx = x + column.width - inset - chevronWidth - shown
      }
      let ty = y + (headerHeight - size.height) / 2
      context.saveGState()
      context.clip(to: CGRect(x: x, y: y, width: column.width, height: headerHeight))
      if sort != nil, let tint = theme.headerSortedBackground {
        tint.setFill()
        NSRect(x: x, y: y, width: column.width, height: headerHeight - 0.5).fill()
      }
      title.draw(at: NSPoint(x: tx.rounded(), y: ty.rounded()))
      if let sort,
        let symbol = NSImage(systemSymbolName: sort.ascending ? "chevron.up" : "chevron.down", accessibilityDescription: nil)?
          .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 9, weight: .bold).applying(.init(paletteColors: [theme.headerText])))
      {
        // The sort chevron sits at the trailing edge of every heading, whatever the text alignment.
        let cx = x + column.width - inset - 10
        symbol.draw(in: NSRect(x: cx, y: y + (headerHeight - 9) / 2, width: 10, height: 9))
      }
      context.restoreGState()
    }
    context.saveGState()
    if !pinned.isEmpty { context.clip(to: CGRect(x: visible.minX + horizontalMargin + pinnedWidth, y: y, width: visible.width, height: headerHeight)) }
    for c in unpinned { drawTitle(c, xOffset: 0) }
    context.restoreGState()
    if !pinned.isEmpty {
      theme.headerBackground.setFill()
      NSRect(x: visible.minX + horizontalMargin, y: y, width: pinnedWidth, height: headerHeight - 0.5).fill()
      for c in pinned { drawTitle(c, xOffset: visible.minX) }
    }
  }

  // MARK: Scrolling

  func scrollToRow(_ displayIndex: Int) {
    guard let scrollView = enclosingScrollView else { return }
    let visible = scrollView.documentVisibleRect
    let r = rowRect(displayIndex)
    var origin = visible.origin
    if r.minY < visible.minY + headerHeight { origin.y = r.minY - headerHeight }
    else if r.maxY > visible.maxY { origin.y = r.maxY - visible.height }
    else { return }
    scrollView.contentView.scroll(to: NSPoint(x: origin.x, y: max(origin.y, 0)))
    scrollView.reflectScrolledClipView(scrollView.contentView)
  }

  @objc private func clipBoundsDidChange(_ note: Notification) {
    let clipWidth = enclosingScrollView?.contentView.bounds.width ?? 0
    if abs(clipWidth - lastClipWidth) > 0.5 {
      lastClipWidth = clipWidth
      relayout()
    }
    // The header and pinned columns float, so the whole visible rect repaints each scroll step.
    setNeedsDisplay(visibleArea)
    updateHostedContent()
    reportScrollGeometry()
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    NotificationCenter.default.removeObserver(self)
    guard let window else { return }
    NotificationCenter.default.addObserver(self, selector: #selector(windowKeyChanged), name: NSWindow.didBecomeKeyNotification, object: window)
    NotificationCenter.default.addObserver(self, selector: #selector(windowKeyChanged), name: NSWindow.didResignKeyNotification, object: window)
    if let clip = enclosingScrollView?.contentView {
      clip.postsBoundsChangedNotifications = true
      clip.postsFrameChangedNotifications = true
      NotificationCenter.default.addObserver(self, selector: #selector(clipBoundsDidChange), name: NSView.boundsDidChangeNotification, object: clip)
      NotificationCenter.default.addObserver(self, selector: #selector(clipBoundsDidChange), name: NSView.frameDidChangeNotification, object: clip)
    }
    isWindowKey = window.isKeyWindow
    relayout()
  }

  @objc private func windowKeyChanged(_ note: Notification) {
    isWindowKey = note.name == NSWindow.didBecomeKeyNotification
    setNeedsDisplay(visibleArea)
  }

  override func becomeFirstResponder() -> Bool { setNeedsDisplay(visibleArea); onFirstResponderChange?(true); return true }
  override func resignFirstResponder() -> Bool { setNeedsDisplay(visibleArea); onFirstResponderChange?(false); return true }

  // MARK: Hover and cursors

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let trackingArea { removeTrackingArea(trackingArea) }
    let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
    addTrackingArea(area)
    trackingArea = area
  }
  override func mouseMoved(with event: NSEvent) {
    let p = convert(event.locationInWindow, from: nil)
    let row = p.y < visibleArea.minY + headerHeight ? nil : displayIndex(at: p)
    if row != hoveredRow {
      if let old = hoveredRow { setNeedsDisplay(rowRect(old)) }
      hoveredRow = row
      if let row { setNeedsDisplay(rowRect(row)) }
    }
  }
  override func mouseExited(with event: NSEvent) {
    if let old = hoveredRow {
      hoveredRow = nil
      setNeedsDisplay(rowRect(old))
    }
  }
  override func resetCursorRects() {
    let visible = visibleArea
    let y = configuration.floatingHeader ? visible.minY : 0
    for c in resolved where c.spec.isResizable {
      let x = columnX(c) + c.width + (c.spec.pin == .leading ? visible.minX : 0)
      addCursorRect(NSRect(x: x - 3, y: y, width: 6, height: headerHeight), cursor: .resizeLeftRight)
    }
  }

  // MARK: Mouse

  private func headerHit(at p: NSPoint) -> (column: FlyResolvedColumn, nearDivider: Bool)? {
    let visible = visibleArea
    let y = configuration.floatingHeader ? visible.minY : 0
    guard p.y >= y, p.y < y + headerHeight else { return nil }
    for c in resolved {
      let x = columnX(c) + (c.spec.pin == .leading ? visible.minX : 0)
      if abs(p.x - (x + c.width)) <= 4 { return (c, true) }
      if p.x >= x, p.x < x + c.width { return (c, false) }
    }
    return nil
  }

  private func cellHandlesDoubleClick(at point: NSPoint) -> Bool {
    let visible = visibleArea
    let ordered = resolved.filter { $0.spec.pin == .leading } + resolved.filter { $0.spec.pin != .leading }
    guard let column = ordered.first(where: {
      let x = columnX($0) + ($0.spec.pin == .leading ? visible.minX : 0)
      return point.x >= x && point.x < x + $0.width
    }) else { return false }
    return engine.columns.first(where: { $0.spec.id == column.id })?.handlesDoubleClick ?? false
  }

  override func mouseDown(with event: NSEvent) {
    guard isInteractionEnabled else { return }
    window?.makeFirstResponder(self)
    let p = convert(event.locationInWindow, from: nil)
    if let hit = headerHit(at: p) {
      if hit.nearDivider, hit.column.spec.isResizable {
        resize = (hit.column.id, p.x, hit.column.width)
      } else if hit.column.spec.isSortable || hit.column.spec.isReorderable {
        headerDragStart = p
        reorderedHeader = false
        headerPress = (hit.column.id, allowsMultiColumnSorting && event.modifierFlags.contains(.shift))
      }
      return
    }
    guard let row = displayIndex(at: p) else {
      if !event.modifierFlags.contains(.command) {
        engine.selection.clear()
        selectionDidChange()
      }
      return
    }
    let id = engine.id(atDisplayIndex: row)
    guard !disabledIDs.contains(id) else { return }
    if event.modifierFlags.contains(.command), let onOpenInNewTab {
      onOpenInNewTab([id]); return
    }
    if event.clickCount >= 2, cellHandlesDoubleClick(at: p) {
      engine.selection.focused = id
      selectionDidChange()
      return
    }
    dragStart = p
    draggingRows = false
    if selectionMode == .none || !selectsOnClick {
      engine.selection.focused = id
      selectionDidChange()
      onRowClick?(id)
      if event.clickCount == 2 { onActivate?([id]) }
      return
    }
    if event.modifierFlags.contains(.command), selectionMode == .multiple {
      engine.selection.toggle(id)
    } else if event.modifierFlags.contains(.shift), selectionMode == .multiple {
      engine.selection.extend(to: id, in: selectableIDs)
    } else if event.clickCount == 2 {
      if !engine.selection.ids.contains(id) { engine.selection.select(id) }
      engine.selection.focused = id
      selectionDidChange()
      onActivate?(activationIDs)
      return
    } else if togglesSelection, event.clickCount == 1,
              event.modifierFlags.intersection([.command, .shift, .option, .control]).isEmpty {
      engine.selection.toggle(id)
    } else if togglesSoleSelection, event.clickCount == 1,
              event.modifierFlags.intersection([.command, .shift, .option, .control]).isEmpty,
              engine.selection.ids == [id] {
      engine.selection.clear()
      engine.selection.focused = id
    } else {
      engine.selection.select(id)
    }
    selectionDidChange()
    onRowClick?(id)
  }

  override func mouseDragged(with event: NSEvent) {
    let p = convert(event.locationInWindow, from: nil)
    guard let resize else {
      if let press = headerPress, let start = headerDragStart,
         abs(p.x - start.x) > 5,
         let spec = engine.specs.first(where: { $0.id == press.column }), spec.isReorderable,
         let target = headerHit(at: p)?.column, target.id != press.column, target.spec.isReorderable {
        let targetX = columnX(target) + (target.spec.pin == .leading ? visibleArea.minX : 0)
        let ordered = engine.layout.orderedIDs(specs: engine.specs).filter { $0 != press.column }
        let targetIndex = ordered.firstIndex(of: target.id)
        let before: FlyColumnID? = p.x > targetX + target.width / 2
          ? targetIndex.flatMap { ordered.indices.contains($0 + 1) ? ordered[$0 + 1] : nil }
          : target.id
        engine.layout.move(press.column, before: before, specs: engine.specs)
        reorderedHeader = true
        relayout()
        return
      }
      guard !draggingRows, let start = dragStart, hypot(p.x - start.x, p.y - start.y) > 4,
            let writers = dragSource?(engine.selection.ids), !writers.isEmpty else { return }
      draggingRows = true
      let items = writers.enumerated().map { index, writer in
        let item = NSDraggingItem(pasteboardWriter: writer)
        let image = NSImage(size: NSSize(width: 120, height: 24))
        image.lockFocus()
        NSColor.controlBackgroundColor.setFill()
        NSRect(x: 0, y: 0, width: 120, height: 24).fill()
        ("\(engine.selection.ids.count) row(s)" as NSString).draw(at: NSPoint(x: 8, y: 4), withAttributes: [.font: theme.cellFont, .foregroundColor: theme.text])
        image.unlockFocus()
        item.setDraggingFrame(NSRect(x: p.x, y: p.y + CGFloat(index) * 3, width: 120, height: 24), contents: image)
        return item
      }
      beginDraggingSession(with: items, event: event, source: self)
      return
    }
    engine.layout.setWidth(resize.startWidth + (p.x - resize.startX), for: resize.column)
    relayout()
    window?.invalidateCursorRects(for: self)
  }

  override func mouseUp(with event: NSEvent) {
    dragStart = nil
    draggingRows = false
    if resize != nil {
      resize = nil
      onLayoutChange?(engine.layout)
      return
    }
    if let press = headerPress {
      headerPress = nil
      headerDragStart = nil
      if reorderedHeader { reorderedHeader = false; onLayoutChange?(engine.layout); return }
      guard engine.specs.first(where: { $0.id == press.column })?.isSortable == true else { return }
      let p = convert(event.locationInWindow, from: nil)
      if let hit = headerHit(at: p), hit.column.id == press.column, !hit.nearDivider {
        engine.sortOrder.toggle(press.column, additive: press.additive)
        onSortChange?(engine.sortOrder)
        invalidateAll()
      }
    }
  }

  override func menu(for event: NSEvent) -> NSMenu? {
    guard isInteractionEnabled else { return nil }
    let p = convert(event.locationInWindow, from: nil)
    if let hit = headerHit(at: p) { return columnMenu(for: hit.column.id) }
    if let row = displayIndex(at: p) {
      let id = engine.id(atDisplayIndex: row)
      guard !disabledIDs.contains(id) else { return nil }
      if selectionMode == .none {
        guard let items = rowContextMenu?(id, []) ?? contextMenu?([id]), !items.isEmpty else { return nil }
        return makeMenu(items)
      }
      if !engine.selection.ids.contains(id) {
        engine.selection.select(id)
        selectionDidChange()
      }
      if let items = rowContextMenu?(id, engine.selection.ids), !items.isEmpty { return makeMenu(items) }
    }
    guard let items = contextMenu?(engine.selection.ids), !items.isEmpty else { return nil }
    return makeMenu(items)
  }

  /// Right-click on the header: show or hide columns, reset widths (the Finder convention).
  private func columnMenu(for column: FlyColumnID) -> NSMenu {
    var items: [FlyMenuItem] = columnContextMenu?(column) ?? []
    if !items.isEmpty { items.append(.separator) }
    for column in engine.columns where column.spec.isHideable {
      let id = column.spec.id
      let hidden = engine.layout.hidden.contains(id)
      items.append(FlyMenuItem((hidden ? "    " : "✓  ") + column.spec.title) { [weak self] in
        guard let self else { return }
        self.engine.layout.toggleHidden(id)
        self.onLayoutChange?(self.engine.layout)
        self.invalidateAll()
      })
    }
    items.append(.separator)
    items.append(FlyMenuItem("Reset Column Widths") { [weak self] in
      guard let self else { return }
      self.engine.layout.widths = [:]
      self.onLayoutChange?(self.engine.layout)
      self.invalidateAll()
    })
    return makeMenu(items)
  }

  private func makeMenu(_ items: [FlyMenuItem]) -> NSMenu {
    let menu = NSMenu()
    menu.autoenablesItems = false
    menuProxies = []
    for item in items {
      if item.isSeparator {
        menu.addItem(.separator())
        continue
      }
      let proxy = FlyMenuProxy(action: item.action)
      menuProxies.append(proxy)
      let mi = NSMenuItem(title: item.title, action: #selector(FlyMenuProxy.performMenuAction(_:)), keyEquivalent: "")
      mi.target = proxy
      mi.isEnabled = item.isEnabled
      menu.addItem(mi)
    }
    return menu
  }

  // MARK: Keyboard

  override func keyDown(with event: NSEvent) {
    guard isInteractionEnabled else { return }
    guard keyboardNavigationEnabled else { super.keyDown(with: event); return }
    let shift = event.modifierFlags.contains(.shift) && selectionMode == .multiple
    let option = event.modifierFlags.contains(.option)
    let order = selectableIDs
    switch event.keyCode {
    case 125: option ? engine.selection.moveToEdge(true, in: order, extending: shift) : engine.selection.move(by: 1, in: order, extending: shift)
    case 126: option ? engine.selection.moveToEdge(false, in: order, extending: shift) : engine.selection.move(by: -1, in: order, extending: shift)
    case 115: engine.selection.moveToEdge(false, in: order, extending: shift)
    case 119: engine.selection.moveToEdge(true, in: order, extending: shift)
    case 116: pageBy(-1, extending: shift, order: order)
    case 121: pageBy(1, extending: shift, order: order)
    case 36, 76:
      let targets = activationIDs.isEmpty ? Set(engine.selection.focused.flatMap { disabledIDs.contains($0) ? nil : $0 }.map { [$0] } ?? []) : activationIDs
      guard !targets.isEmpty else { return }
      if let onOpenInNewTab, event.modifierFlags.contains(.command) { onOpenInNewTab(targets) }
      else { onActivate?(targets) }
      return
    default:
      super.keyDown(with: event)
      return
    }
    selectionDidChange()
    if let focused = engine.selection.focused, let i = engine.displayIndex(of: focused) { scrollToRow(i) }
  }

  private func pageBy(_ direction: Int, extending: Bool, order: [Row.ID]) {
    let visibleRows = max(Int((visibleArea.height - headerHeight) / rowHeight) - 1, 1)
    engine.selection.move(by: direction * visibleRows, in: order, extending: extending)
  }

  override func selectAll(_ sender: Any?) {
    guard keyboardNavigationEnabled, isInteractionEnabled, selectionMode == .multiple else { return }
    engine.selection.selectAll(selectableIDs)
    selectionDidChange()
  }
  override func cancelOperation(_ sender: Any?) {
    engine.selection.clear()
    selectionDidChange()
  }

  private var activationIDs: Set<Row.ID> {
    if focusedActivationOnly, let focused = engine.selection.focused, !disabledIDs.contains(focused) { return [focused] }
    return engine.selection.ids.subtracting(disabledIDs)
  }

  private var selectableIDs: [Row.ID] { engine.displayIDs.filter { !disabledIDs.contains($0) } }

  private func selectionDidChange() {
    engine.selection.constrain(to: selectionMode, disabled: disabledIDs)
    onSelectionChange?(engine.selection)
    setNeedsDisplay(visibleArea)
  }

  private func reportScrollGeometry() {
    let rect = visibleArea, size = bounds.size
    let geometryChanged = lastScrollGeometry.map { $0.0 != rect || $0.1 != size } ?? true
    lastScrollGeometry = (rect, size)
    let contentHeight = headerHeight + geometry.contentHeight
    let reachedEnd = rect.maxY >= contentHeight - 100
    let endChanged = lastScrollEnd.map { $0.0 != reachedEnd || $0.1 != contentHeight } ?? true
    lastScrollEnd = (reachedEnd, contentHeight)
    guard geometryChanged || endChanged else { return }
    DispatchQueue.main.async { [weak self] in
      if geometryChanged { self?.onScrollChange?(rect, size) }
      if reachedEnd && endChanged { self?.onScrollEndVisible?() }
    }
  }

  func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { [.copy, .move] }
  private func dropRow(_ info: NSDraggingInfo) -> Row.ID? {
    let p = convert(info.draggingLocation, from: nil)
    guard headerHit(at: p) == nil, let index = displayIndex(at: p) else { return nil }
    return engine.id(atDisplayIndex: index)
  }
  override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { isInteractionEnabled ? validateDrop?(sender, dropRow(sender)) ?? [] : [] }
  override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { isInteractionEnabled ? validateDrop?(sender, dropRow(sender)) ?? [] : [] }
  override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { !(isInteractionEnabled ? validateDrop?(sender, dropRow(sender)) ?? [] : []).isEmpty }
  override func performDragOperation(_ sender: NSDraggingInfo) -> Bool { isInteractionEnabled ? performDrop?(sender, dropRow(sender)) ?? false : false }

  // MARK: Accessibility

  override func isAccessibilityElement() -> Bool { true }
  override func accessibilityRole() -> NSAccessibility.Role? { .table }
  override func accessibilityLabel() -> String? { "Table, \(engine.count) rows, \(resolved.count) columns" }
  override func accessibilityRowCount() -> Int { engine.count }
  override func accessibilityColumnCount() -> Int { resolved.count }

  /// Bound native AX objects to the viewport plus the keyboard-focused row. Hosted controls
  /// retain their own semantic children rather than becoming flattened text labels.
  private func accessibilityRowElements() -> [FlyTableAccessibilityElement] {
    let visible = visibleArea
    var indexes = Array(geometry.rows(in: (visible.minY - headerHeight)...(visible.maxY - headerHeight)))
    if let focused = engine.selection.focused, let index = engine.displayIndex(of: focused), !indexes.contains(index) { indexes.append(index) }
    var active: Set<Row.ID> = []
    let result = indexes.sorted().map { index -> FlyTableAccessibilityElement in
      let row = engine.row(atDisplayIndex: index)
      active.insert(row.id)
      let rowID = row.id
      let element = accessibleRows[rowID] ?? FlyTableAccessibilityElement { [weak self] in
        guard let self, self.isInteractionEnabled, !self.disabledIDs.contains(rowID),
              let currentIndex = self.engine.displayIndex(of: rowID) else { return false }
        self.engine.selection.select(rowID)
        self.selectionDidChange()
        self.scrollToRow(currentIndex)
        self.onActivate?([rowID])
        return true
      }
      accessibleRows[row.id] = element
      element.setAccessibilityRole(.row)
      element.setAccessibilityParent(self)
      element.setAccessibilityIndex(index)
      element.setAccessibilityRowIndexRange(NSRange(location: index, length: 1))
      element.setAccessibilityFrameInParentSpace(rowRect(index))
      element.setAccessibilitySelected(engine.selection.ids.contains(row.id))
      element.setAccessibilityEnabled(isInteractionEnabled && !disabledIDs.contains(row.id))
      element.setAccessibilityLabel(resolved.map { engine.value(atDisplayIndex: index, column: $0.id).displayString() }.joined(separator: ", "))
      if let fullRow = hosted[HostedKey(row: row.id, column: nil)] {
        element.setAccessibilityChildren(fullRow.host.accessibilityChildren() ?? [fullRow.host])
      } else {
        let children: [Any] = resolved.enumerated().map { columnIndex, column in
          let key = HostedKey(row: row.id, column: column.id)
          if let custom = hosted[key] { return custom.host }
          let cell = accessibleCells[key] ?? FlyTableAccessibilityElement()
          accessibleCells[key] = cell
          cell.setAccessibilityRole(.cell)
          cell.setAccessibilityParent(element)
          cell.setAccessibilityRowIndexRange(NSRange(location: index, length: 1))
          cell.setAccessibilityColumnIndexRange(NSRange(location: columnIndex, length: 1))
          cell.setAccessibilityLabel(column.spec.title)
          cell.setAccessibilityValue(engine.value(atDisplayIndex: index, column: column.id).displayString())
          cell.setAccessibilityEnabled(isInteractionEnabled && !disabledIDs.contains(row.id))
          cell.setAccessibilityFrameInParentSpace(CGRect(x: columnX(column), y: 0, width: column.width, height: rowRect(index).height))
          return cell
        }
        element.setAccessibilityChildren(children)
      }
      return element
    }
    accessibleRows = accessibleRows.filter { active.contains($0.key) }
    accessibleCells = accessibleCells.filter { $0.key.row.map(active.contains) ?? true }
    return result
  }

  override func accessibilityRows() -> [Any]? { accessibilityRowElements() }
  override func accessibilityVisibleRows() -> [Any]? { accessibilityRowElements().filter { $0.accessibilityFrameInParentSpace().intersects(visibleArea) } }
  override func accessibilitySelectedRows() -> [Any]? { accessibilityRowElements().filter { $0.isAccessibilitySelected() } }
  override func accessibilityChildren() -> [Any]? {
    var headers: [Any] = []
    if configuration.showsHeader {
      headers = resolved.enumerated().map { index, column in
        let key = HostedKey(row: nil, column: column.id)
        if let custom = hosted[key] { return custom.host }
        let columnID = column.id
        let header = accessibleCells[key] ?? FlyTableAccessibilityElement { [weak self] in
          guard let self, self.isInteractionEnabled,
                self.engine.specs.first(where: { $0.id == columnID })?.isSortable == true else { return false }
          self.engine.sortOrder.toggle(columnID)
          self.onSortChange?(self.engine.sortOrder)
          self.invalidateAll()
          return true
        }
        accessibleCells[key] = header
        header.setAccessibilityRole(column.spec.isSortable ? .button : .staticText)
        header.setAccessibilityParent(self)
        header.setAccessibilityLabel(column.spec.title)
        header.setAccessibilityValue(engine.sortOrder.descriptor(for: column.id).map { $0.ascending ? "Ascending" : "Descending" } ?? "Unsorted")
        header.setAccessibilityColumnIndexRange(NSRange(location: index, length: 1))
        header.setAccessibilityFrameInParentSpace(CGRect(x: columnX(column) + (column.spec.pin == .leading ? visibleArea.minX : 0), y: visibleArea.minY, width: column.width, height: headerHeight))
        return header
      }
    }
    return headers + accessibilityRowElements()
  }

}

@MainActor
final class FlyMenuProxy: NSObject {
  let action: @MainActor @Sendable () -> Void
  init(action: @escaping @MainActor @Sendable () -> Void) { self.action = action }
  @objc func performMenuAction(_ sender: Any?) { action() }
}
#endif

#if os(macOS)
/// A shaped cell ready to draw: one text line, or pills.
enum FlyRenderedCell {
  case line(CTLine)
  case badges([FlyRenderedBadge])
}

struct FlyRenderedBadge {
  let line: CTLine
  let textWidth: CGFloat
  let symbol: NSImage?
  let tint: FlyTint
  let fill: FlyBadgeFill
}
#endif

#if os(macOS)
@MainActor
private final class FlyHostedCell: NSView {
  let host = FlyCellHostingView(rootView: AnyView(EmptyView()))
  override var isFlipped: Bool { true }
  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
    layer?.masksToBounds = true
    addSubview(host)
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

@MainActor
private final class FlyCellHostingView: NSHostingView<AnyView> {
  var forwardMouseDown: ((NSEvent) -> Void)?
  override func mouseDown(with event: NSEvent) {
    forwardMouseDown?(event)
    super.mouseDown(with: event)
  }
}
#endif

#if os(macOS)
// AppKit delivers native accessibility actions on the main thread. Keep the action
// immutable and actor-qualified across the nonisolated Objective-C entry point.
private final class FlyTableAccessibilityElement: NSAccessibilityElement {
  private let press: (@MainActor @Sendable () -> Bool)?
  init(press: (@MainActor @Sendable () -> Bool)? = nil) {
    self.press = press
    super.init()
  }
  override func accessibilityPerformPress() -> Bool {
    let action = press
    return MainActor.assumeIsolated { action?() ?? false }
  }
}
#endif
