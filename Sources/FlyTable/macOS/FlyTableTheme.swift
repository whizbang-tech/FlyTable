#if os(macOS)
import AppKit
import FlyTableCore

/// Flat theme: every colour and font the renderer uses. FlyUI supplies its own from tokens.
public struct FlyTableTheme: @unchecked Sendable {
  public var cellFont: NSFont
  public var numericFont: NSFont
  public var headerFont: NSFont
  public var background: NSColor
  public var alternateRowBackground: NSColor
  public var headerBackground: NSColor
  public var text: NSColor
  public var secondaryText: NSColor
  public var selectedText: NSColor
  public var headerText: NSColor
  public var separator: NSColor
  public var hover: NSColor
  public var selectionEmphasized: NSColor
  public var selectionUnemphasized: NSColor
  public var cellInset: CGFloat
  public var insetStyleMargin: CGFloat
  public var selectionCornerRadius: CGFloat

  public static let system = FlyTableTheme(
    cellFont: .systemFont(ofSize: NSFont.systemFontSize),
    numericFont: .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
    headerFont: .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold),
    background: .controlBackgroundColor,
    alternateRowBackground: NSColor.alternatingContentBackgroundColors.count > 1 ? NSColor.alternatingContentBackgroundColors[1] : .controlBackgroundColor,
    headerBackground: .controlBackgroundColor,
    text: .labelColor,
    secondaryText: .secondaryLabelColor,
    selectedText: .alternateSelectedControlTextColor,
    headerText: .secondaryLabelColor,
    separator: .separatorColor,
    hover: NSColor.labelColor.withAlphaComponent(0.045),
    selectionEmphasized: .selectedContentBackgroundColor,
    selectionUnemphasized: .unemphasizedSelectedContentBackgroundColor,
    cellInset: 8,
    insetStyleMargin: 10,
    selectionCornerRadius: 6
  )

  public init(
    cellFont: NSFont, numericFont: NSFont, headerFont: NSFont, background: NSColor, alternateRowBackground: NSColor,
    headerBackground: NSColor, text: NSColor, secondaryText: NSColor, selectedText: NSColor, headerText: NSColor,
    separator: NSColor, hover: NSColor, selectionEmphasized: NSColor, selectionUnemphasized: NSColor,
    cellInset: CGFloat, insetStyleMargin: CGFloat, selectionCornerRadius: CGFloat
  ) {
    self.cellFont = cellFont
    self.numericFont = numericFont
    self.headerFont = headerFont
    self.background = background
    self.alternateRowBackground = alternateRowBackground
    self.headerBackground = headerBackground
    self.text = text
    self.secondaryText = secondaryText
    self.selectedText = selectedText
    self.headerText = headerText
    self.separator = separator
    self.hover = hover
    self.selectionEmphasized = selectionEmphasized
    self.selectionUnemphasized = selectionUnemphasized
    self.cellInset = cellInset
    self.insetStyleMargin = insetStyleMargin
    self.selectionCornerRadius = selectionCornerRadius
  }
}

/// Everything the renderer needs besides the engine.
public struct FlyTableConfiguration: @unchecked Sendable {
  public var style: FlyTableStyle = .inset
  public var density: FlyRowDensity = .comfortable
  public var alternatingRows = false
  public var rowSeparators = false
  public var columnSeparators = false
  public var floatingHeader = true
  public var theme: FlyTableTheme = .system
  public init() {}
}
#endif
