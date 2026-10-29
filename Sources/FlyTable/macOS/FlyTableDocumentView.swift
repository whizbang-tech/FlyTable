#if os(macOS)
import AppKit
import CoreText
import SwiftUI
import FlyTableCore

/// The custom-drawn table body. One view, sized to the whole content, draws only the visible
/// rows × visible columns from cached Core Text lines, with the floating header and pinned
/// columns painted in the same pass. Cost per frame is O(visible cells).
@MainActor
final class FlyTableDocumentView<Row: Identifiable>: NSView where Row.ID: Hashable & Sendable {
  let engine: FlyTableEngine<Row>
  var configuration = FlyTableConfiguration() { didSet { invalidateAll() } }

  var onSelectionChange: ((FlySelection<Row.ID>) -> Void)?
  var onSortChange: ((FlySortOrder) -> Void)?
  var onLayoutChange: ((FlyColumnLayoutState) -> Void)?
  var onActivate: ((Set<Row.ID>) -> Void)?
  var contextMenu: ((Set<Row.ID>) -> [FlyMenuItem])?

  private(set) var resolved: [FlyResolvedColumn] = []
  private var geometry = FlyRowGeometry(rowCount: 0, rowHeight: 28)
  private let lines = FlyCellCache<FlyRenderedCell>(capacity: 30_000)
  private var fitWidths: [FlyColumnID: CGFloat] = [:]
  private var fitRevision = -1
  private var hoveredRow: Int?
  private var isWindowKey = true
  private var resize: (column: FlyColumnID, startX: CGFloat, startWidth: CGFloat)?
  private var headerPress: (column: FlyColumnID, additive: Bool)?
  private var menuProxies: [FlyMenuProxy] = []
  private var trackingArea: NSTrackingArea?
  private var lastClipWidth: CGFloat = 0

  // Hosted cells: one hosting view per visible (row, hosted column), recycled through a pool.
  private struct HostedKey: Hashable { let row: Row.ID; let column: FlyColumnID }
  private var hostedColumns: [FlyColumnID: FlyColumn<Row>] = [:]
  private var hostedViews: [HostedKey: FlyHostingView] = [:]
  private var hostedPool: [FlyHostingView] = []
  private var hostedGeneration = 0
  private let pinnedHost = FlyHostContainer(frame: .zero)
  private let unpinnedHost = FlyHostContainer(frame: .zero)

  init(engine: FlyTableEngine<Row>) {
    self.engine = engine
    super.init(frame: .zero)
    wantsLayer = false
    canDrawConcurrently = true
    for host in [unpinnedHost, pinnedHost] {
      host.isHidden = true
      addSubview(host)
    }
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var isFlipped: Bool { true }
  override var acceptsFirstResponder: Bool { true }
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
  override var isOpaque: Bool { configuration.style != .plain }

  var rowHeight: CGFloat { configuration.density.rowHeight }
  var headerHeight: CGFloat { rowHeight }
  private var theme: FlyTableTheme { configuration.theme }
  private var horizontalMargin: CGFloat { configuration.style == .inset ? theme.insetStyleMargin : 0 }

  // MARK: Layout

  func relayout() {
    let clipWidth = enclosingScrollView?.contentView.bounds.width ?? bounds.width
    geometry = FlyRowGeometry(rowCount: engine.count, rowHeight: rowHeight)
    hostedColumns = Dictionary(engine.columns.filter(\.isHosted).map { ($0.spec.id, $0) }, uniquingKeysWith: { a, _ in a })
    computeFitWidthsIfNeeded()
    let available = max(clipWidth - horizontalMargin * 2, 0)
    resolved = FlyColumnLayoutResolver.resolve(specs: engine.specs, state: engine.layout, availableWidth: available, fitWidths: fitWidths)
    let total = (resolved.last?.maxX ?? 0) + horizontalMargin * 2
    let height = headerHeight + geometry.contentHeight
    let newSize = NSSize(width: max(total, clipWidth), height: max(height, enclosingScrollView?.contentView.bounds.height ?? 0))
    if frame.size != newSize { setFrameSize(newSize) }
    lines.removeAll()
    needsDisplay = true
    updateHostedCells()
  }

  /// Repaint the visible rows and refresh hosted cell state (selection, focus, hover).
  func refreshVisible() {
    setNeedsDisplay(visibleArea)
    updateHostedCells()
  }

  /// Hosted content closures changed (the host view re-rendered): re-evaluate every visible hosted cell.
  func hostedContentDidChange() {
    hostedGeneration &+= 1
    hostedColumns = Dictionary(engine.columns.filter(\.isHosted).map { ($0.spec.id, $0) }, uniquingKeysWith: { a, _ in a })
    updateHostedCells()
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
    for column in engine.columns where column.spec.width == .fit && !column.isHosted {
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
    for column in unpinned where hostedColumns[column.id] == nil { drawCells(column, rows: rows, xOffset: 0, context: context) }
    context.restoreGState()
    if !pinned.isEmpty {
      let pinRect = NSRect(x: scrollX + horizontalMargin, y: dirtyRect.minY, width: pinnedWidth, height: dirtyRect.height)
      if configuration.style != .plain {
        theme.background.setFill()
        pinRect.fill()
      }
      drawRowBackgrounds(rows, visible: visible, clip: pinRect)
      for column in pinned where hostedColumns[column.id] == nil { drawCells(column, rows: rows, xOffset: scrollX, context: context) }
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
    let emphasized = isWindowKey && window?.firstResponder === self
    let inset = theme.cellInset
    let x = columnX(column) + xOffset
    let textWidth = max(column.width - inset * 2, 1)
    let font = column.spec.alignment == .numeric ? theme.numericFont : theme.cellFont
    context.saveGState()
    context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
    for i in rows {
      let key = FlyCellKey(row: i, column: column.id, revision: engine.revision)
      let cell = lines.value(for: key) { render(engine.value(atDisplayIndex: i, column: column.id), font: font, width: textWidth) }
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
    let y = configuration.floatingHeader ? visible.minY : 0
    let headerRect = NSRect(x: visible.minX, y: y, width: visible.width, height: headerHeight)
    theme.headerBackground.setFill()
    headerRect.fill()
    theme.separator.setFill()
    NSRect(x: visible.minX + horizontalMargin, y: headerRect.maxY - 0.5, width: visible.width - horizontalMargin * 2, height: 0.5).fill()

    func drawTitle(_ column: FlyResolvedColumn, xOffset: CGFloat) {
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

  // MARK: Hosted cells

  /// Place a hosting view over every visible cell of a hosted column, reusing the view a row
  /// already has, taking one from the pool otherwise, and pooling the views of rows that left.
  /// The per-scroll cost is a frame update per visible hosted cell; content is re-evaluated only
  /// when the row, its state or the host view's generation changed.
  private func updateHostedCells() {
    let hosted = resolved.filter { hostedColumns[$0.id] != nil }
    guard !hosted.isEmpty, engine.count > 0 else {
      for (_, view) in hostedViews { recycle(view) }
      hostedViews.removeAll()
      pinnedHost.place(.zero)
      unpinnedHost.place(.zero)
      return
    }
    let visible = visibleArea
    let headerY = configuration.floatingHeader ? visible.minY : 0
    let top = max(visible.minY, headerY + headerHeight)
    let bodyHeight = max(visible.maxY - top, 0)
    let pinnedW = pinnedWidth
    let margin = horizontalMargin
    pinnedHost.place(pinnedW > 0 ? NSRect(x: visible.minX + margin, y: top, width: pinnedW, height: bodyHeight) : .zero)
    unpinnedHost.place(NSRect(x: visible.minX + margin + pinnedW, y: top, width: max(visible.width - margin * 2 - pinnedW, 0), height: bodyHeight))

    let emphasized = isWindowKey && window?.firstResponder === self
    let lower = top - headerHeight, upper = visible.maxY - headerHeight
    let rows = upper > lower ? geometry.rows(in: lower...upper) : 0..<0
    let inset = theme.cellInset
    var live = Set<HostedKey>()
    live.reserveCapacity(rows.count * hosted.count)
    for column in hosted {
      guard let definition = hostedColumns[column.id], let content = definition.content else { continue }
      let isPinned = column.spec.pin == .leading
      let x = columnX(column) + (isPinned ? visible.minX : 0) + inset
      let width = max(column.width - inset * 2, 1)
      let container = isPinned ? pinnedHost : unpinnedHost
      let alignment = column.spec.alignment.swiftUIAlignment
      for i in rows {
        let id = engine.id(atDisplayIndex: i)
        let key = HostedKey(row: id, column: column.id)
        live.insert(key)
        let view = hostedViews[key] ?? dequeueHostingView()
        hostedViews[key] = view
        let state = FlyCellState(
          isSelected: engine.selection.ids.contains(id), isEmphasized: emphasized && engine.selection.ids.contains(id),
          isHovered: hoveredRow == i, displayIndex: i)
        if view.renderedKey != AnyHashable(key) || view.renderedGeneration != hostedGeneration || view.renderedState != state {
          view.rootView = AnyView(FlyHostedCell(content: content(engine.row(atDisplayIndex: i)), state: state, alignment: alignment))
          view.renderedKey = AnyHashable(key)
          view.renderedGeneration = hostedGeneration
          view.renderedState = state
        }
        view.isInteractive = definition.isInteractive
        view.onMouseDown = { [weak self] in
          guard let self else { return }
          self.window?.makeFirstResponder(self)
          if !self.engine.selection.ids.contains(id) {
            self.engine.selection.select(id)
            self.selectionDidChange()
          }
        }
        if view.superview !== container { container.addSubview(view) }
        let r = rowRect(i)
        let frame = NSRect(x: x, y: r.minY, width: width, height: r.height)
        if view.frame != frame { view.frame = frame }
        view.isHidden = false
      }
    }
    for (key, view) in hostedViews where !live.contains(key) {
      hostedViews.removeValue(forKey: key)
      recycle(view)
    }
  }

  private func dequeueHostingView() -> FlyHostingView {
    if let view = hostedPool.popLast() { return view }
    return FlyHostingView(rootView: AnyView(EmptyView()))
  }

  private func recycle(_ view: FlyHostingView) {
    view.isHidden = true
    view.removeFromSuperview()
    view.renderedKey = nil
    view.renderedState = nil
    if hostedPool.count < 128 { hostedPool.append(view) } else { view.rootView = AnyView(EmptyView()) }
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
    updateHostedCells()
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
    refreshVisible()
  }

  override func becomeFirstResponder() -> Bool { refreshVisible(); return true }
  override func resignFirstResponder() -> Bool { refreshVisible(); return true }

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
      if !hostedColumns.isEmpty { updateHostedCells() }
    }
  }
  override func mouseExited(with event: NSEvent) {
    if let old = hoveredRow {
      hoveredRow = nil
      setNeedsDisplay(rowRect(old))
      if !hostedColumns.isEmpty { updateHostedCells() }
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

  override func mouseDown(with event: NSEvent) {
    window?.makeFirstResponder(self)
    let p = convert(event.locationInWindow, from: nil)
    if let hit = headerHit(at: p) {
      if hit.nearDivider, hit.column.spec.isResizable {
        resize = (hit.column.id, p.x, hit.column.width)
      } else if hit.column.spec.isSortable {
        headerPress = (hit.column.id, event.modifierFlags.contains(.shift))
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
    if event.modifierFlags.contains(.command) {
      engine.selection.toggle(id)
    } else if event.modifierFlags.contains(.shift) {
      engine.selection.extend(to: id, in: engine.displayIDs)
    } else if event.clickCount == 2 {
      if !engine.selection.ids.contains(id) { engine.selection.select(id) }
      selectionDidChange()
      onActivate?(engine.selection.ids)
      return
    } else {
      engine.selection.select(id)
    }
    selectionDidChange()
  }

  override func mouseDragged(with event: NSEvent) {
    guard let resize else { return }
    let p = convert(event.locationInWindow, from: nil)
    engine.layout.setWidth(resize.startWidth + (p.x - resize.startX), for: resize.column)
    relayout()
    window?.invalidateCursorRects(for: self)
  }

  override func mouseUp(with event: NSEvent) {
    if resize != nil {
      resize = nil
      onLayoutChange?(engine.layout)
      return
    }
    if let press = headerPress {
      headerPress = nil
      let p = convert(event.locationInWindow, from: nil)
      if let hit = headerHit(at: p), hit.column.id == press.column, !hit.nearDivider {
        engine.sortOrder.toggle(press.column, additive: press.additive)
        onSortChange?(engine.sortOrder)
        invalidateAll()
      }
    }
  }

  override func menu(for event: NSEvent) -> NSMenu? {
    let p = convert(event.locationInWindow, from: nil)
    if headerHit(at: p) != nil { return columnMenu() }
    if let row = displayIndex(at: p) {
      let id = engine.id(atDisplayIndex: row)
      if !engine.selection.ids.contains(id) {
        engine.selection.select(id)
        selectionDidChange()
      }
    }
    guard let items = contextMenu?(engine.selection.ids), !items.isEmpty else { return nil }
    return makeMenu(items)
  }

  /// Right-click on the header: show or hide columns, reset widths (the Finder convention).
  private func columnMenu() -> NSMenu {
    var items: [FlyMenuItem] = []
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
    let shift = event.modifierFlags.contains(.shift)
    let option = event.modifierFlags.contains(.option)
    let order = engine.displayIDs
    switch event.keyCode {
    case 125: option ? engine.selection.moveToEdge(true, in: order, extending: shift) : engine.selection.move(by: 1, in: order, extending: shift)
    case 126: option ? engine.selection.moveToEdge(false, in: order, extending: shift) : engine.selection.move(by: -1, in: order, extending: shift)
    case 115: engine.selection.moveToEdge(false, in: order, extending: shift)
    case 119: engine.selection.moveToEdge(true, in: order, extending: shift)
    case 116: pageBy(-1, extending: shift, order: order)
    case 121: pageBy(1, extending: shift, order: order)
    case 36, 76:
      if !engine.selection.isEmpty { onActivate?(engine.selection.ids) }
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
    engine.selection.selectAll(engine.displayIDs)
    selectionDidChange()
  }
  override func cancelOperation(_ sender: Any?) {
    engine.selection.clear()
    selectionDidChange()
  }

  private func selectionDidChange() {
    onSelectionChange?(engine.selection)
    refreshVisible()
  }

  // MARK: Accessibility (table-level; per-cell elements are scheduled)

  override func isAccessibilityElement() -> Bool { true }
  override func accessibilityRole() -> NSAccessibility.Role? { .table }
  override func accessibilityLabel() -> String? { "Table, \(engine.count) rows, \(resolved.count) columns" }
  override func accessibilityRowCount() -> Int { engine.count }
  override func accessibilityColumnCount() -> Int { resolved.count }
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
