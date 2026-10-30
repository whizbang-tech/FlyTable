#if os(macOS)
import AppKit
import Testing
import FlyTableCore
@testable import FlyTable

@Suite @MainActor struct HeaderGradientTests {
  private struct Row: Identifiable { let id: Int; let name: String }

  @Test func gradientIsOptInAndParticipatesInThemeInvalidation() {
    #expect(FlyTableTheme.system.headerGradient == nil)
    #expect(FlyTableTheme.flyUI.headerGradient == nil)
    var changed = FlyTableTheme.system
    changed.headerGradient = .init(startColor: .white, endColor: .black)
    #expect(changed != .system)
    var moved = changed
    moved.headerGradient?.endPoint = CGPoint(x: 0, y: 1)
    #expect(moved != changed)
    var recolored = changed
    recolored.headerGradient?.endColor = .red
    #expect(recolored != changed)
    var sorted = changed
    sorted.headerSortedBackground = .red
    #expect(sorted != changed)
  }

  @Test func pinnedHeadingsShareTheVisibleGradientWhileScrolling() throws {
    let gradient = FlyTableHeaderGradient(startColor: .black, endColor: .white,
      endPoint: CGPoint(x: 1, y: 0))
    let plain = try renderHeader(pinned: false, gradient: gradient)
    let pinned = try renderHeader(pinned: true, gradient: gradient)
    let scrolled = try renderHeader(pinned: true, offset: CGPoint(x: 80, y: 40), gradient: gradient)
    for x in [20, 80, 119, 121, 180, 300, 380] {
      let reference = try pixel(plain, x: x)
      #expect(abs(try pixel(pinned, x: x).redComponent - reference.redComponent) < 0.03)
      #expect(abs(try pixel(scrolled, x: x).redComponent - reference.redComponent) < 0.03)
    }
    #expect(try pixel(pinned, x: 20).redComponent < 0.15)
    #expect(try pixel(pinned, x: 380).redComponent > 0.85)
    #expect(abs(try pixel(pinned, x: 119).redComponent - pixel(pinned, x: 121).redComponent) < 0.03)
  }

  @Test func flatFallbackAndSortedHeadingRemainVisible() throws {
    let flat = try renderHeader(pinned: true, gradient: nil)
    #expect(try pixel(flat, x: 40).redComponent < 0.02)
    #expect(try pixel(flat, x: 300).redComponent < 0.02)
    let gradient = FlyTableHeaderGradient(startColor: .black, endColor: .white,
      endPoint: CGPoint(x: 1, y: 0))
    for (column, x) in [("first", 40), ("second", 200)] {
      let sorted = try renderHeader(pinned: true, gradient: gradient, sorted: FlyColumnID(column))
      let color = try pixel(sorted, x: x)
      #expect(color.redComponent > color.greenComponent + 0.3)
    }
  }

  @Test func normalizedGradientPointsUseTopLeftCoordinates() throws {
    let gradient = FlyTableHeaderGradient(startColor: .black, endColor: .white,
      endPoint: CGPoint(x: 0, y: 1))
    let image = try renderHeader(pinned: true, offset: CGPoint(x: 80, y: 40), gradient: gradient)
    #expect(try pixel(image, x: 40, y: 2).redComponent < 0.1)
    #expect(try pixel(image, x: 40, y: 37).redComponent > 0.9)
    #expect(abs(try pixel(image, x: 40).redComponent - pixel(image, x: 300).redComponent) < 0.03)
  }

  /// Renders only this synthetic view into a bitmap; no desktop/window capture is involved.
  private func renderHeader(pinned: Bool, offset: CGPoint = .zero,
                            gradient: FlyTableHeaderGradient?, sorted: FlyColumnID? = nil) throws -> NSBitmapImageRep {
    _ = NSApplication.shared
    let engine = FlyTableEngine<Row>()
    var first = FlyColumn<Row>("", id: "first", value: \.name).width(.fixed(120))
    if pinned { first = first.pinned() }
    engine.setColumns([first, FlyColumn<Row>("", id: "second", value: \.name).width(.fixed(600))])
    engine.setRows((0..<30).map { Row(id: $0, name: "Synthetic") }, revision: 1)
    if let sorted { engine.sortOrder = FlySortOrder([FlySortDescriptor(column: sorted)]) }
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 180),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 180))
    window.contentView = scroll
    let view = FlyTableDocumentView(engine: engine)
    var configuration = FlyTableConfiguration()
    configuration.style = .card
    configuration.headerHeight = 40
    configuration.theme.headerBackground = .black
    configuration.theme.headerGradient = gradient
    configuration.theme.headerText = .clear
    configuration.theme.separator = .clear
    configuration.theme.headerSortedBackground = NSColor.red.withAlphaComponent(0.5)
    view.configuration = configuration
    scroll.documentView = view
    view.relayout()
    scroll.contentView.scroll(to: offset)
    scroll.reflectScrolledClipView(scroll.contentView)
    let rect = NSRect(x: offset.x, y: offset.y, width: 400, height: 40)
    let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 400, pixelsHigh: 40,
      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
      colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
    view.cacheDisplay(in: rect, to: bitmap)
    return bitmap
  }

  private func pixel(_ bitmap: NSBitmapImageRep, x: Int, y: Int = 10) throws -> NSColor {
    try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
  }
}
#endif
