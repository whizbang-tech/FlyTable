#if os(macOS)
import AppKit

/// The native scroll surface: vertical and horizontal scrolling, overlay scrollers, the document
/// view sized by the table.
@MainActor
final class FlyTableScrollView: NSScrollView {
  override init(frame: NSRect) {
    super.init(frame: frame)
    hasVerticalScroller = true
    hasHorizontalScroller = true
    autohidesScrollers = true
    drawsBackground = false
    borderType = .noBorder
    contentView.postsBoundsChangedNotifications = true
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}
#endif
