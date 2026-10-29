#if os(macOS)
import AppKit
import SwiftUI
import FlyTableCore

/// One hosted cell: an `NSHostingView` the renderer places over a visible row and recycles when the
/// row scrolls out. Sizing is manual (`sizingOptions = []`), so SwiftUI never drives the table layout.
@MainActor
final class FlyHostingView: NSHostingView<AnyView> {
  var isInteractive = false
  var onMouseDown: (() -> Void)?
  var renderedKey: AnyHashable?
  var renderedGeneration = -1
  var renderedState: FlyCellState?

  required init(rootView: AnyView) {
    super.init(rootView: rootView)
    sizingOptions = []
    translatesAutoresizingMaskIntoConstraints = true
  }
  @objc required dynamic init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  /// Non-interactive cells are invisible to hit testing, so clicks select the row beneath.
  override func hitTest(_ point: NSPoint) -> NSView? { isInteractive ? super.hitTest(point) : nil }
  override func mouseDown(with event: NSEvent) {
    onMouseDown?()
    super.mouseDown(with: event)
  }
}

/// Clips hosted cells to the body (below the header, beside the pinned columns). Its bounds origin
/// tracks its frame origin so cell frames are given in document coordinates.
@MainActor
final class FlyHostContainer: NSView {
  override var isFlipped: Bool { true }
  override init(frame: NSRect) {
    super.init(frame: frame)
    clipsToBounds = true
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
  /// Empty space passes through to the table body.
  override func hitTest(_ point: NSPoint) -> NSView? {
    let hit = super.hitTest(point)
    return hit === self ? nil : hit
  }
  func place(_ rect: NSRect) {
    if frame != rect { frame = rect }
    if bounds.origin != rect.origin { setBoundsOrigin(rect.origin) }
    isHidden = rect.isEmpty
  }
}

/// Wraps hosted content with the cell's state and alignment.
struct FlyHostedCell: View {
  let content: AnyView
  let state: FlyCellState
  let alignment: Alignment

  var body: some View {
    content
      .environment(\.flyCellState, state)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
  }
}

extension FlyColumnAlignment {
  var swiftUIAlignment: Alignment {
    switch self {
    case .leading: .leading
    case .center: .center
    case .trailing, .numeric: .trailing
    }
  }
}
#endif
