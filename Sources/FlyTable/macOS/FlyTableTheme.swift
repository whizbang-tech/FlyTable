#if os(macOS)
import AppKit
import FlyTableCore

/// Flat theme: every colour and font the renderer uses. `system` matches Finder and Mail;
/// `flyUI` matches FlyUI's default table (surface, raised header strip, tinted sorted heading,
/// striped rows, hairline rules, tinted selection with a focus edge).
public struct FlyTableTheme: @unchecked Sendable {
  public var cellFont: NSFont
  public var numericFont: NSFont
  public var headerFont: NSFont
  public var background: NSColor
  public var alternateRowBackground: NSColor
  public var headerBackground: NSColor
  /// Fill behind the sorted column's heading; nil leaves the header flat.
  public var headerSortedBackground: NSColor?
  public var text: NSColor
  public var secondaryText: NSColor
  public var selectedText: NSColor
  public var headerText: NSColor
  public var separator: NSColor
  public var hover: NSColor
  public var selectionEmphasized: NSColor
  public var selectionUnemphasized: NSColor
  /// Stroke drawn inside a selected row in the key window; nil draws none.
  public var selectionEdge: NSColor?
  public var cellInset: CGFloat
  public var insetStyleMargin: CGFloat
  public var selectionCornerRadius: CGFloat
  /// The `.card` style's rounded border.
  public var cardCornerRadius: CGFloat
  public var cardBorder: NSColor

  public static let system = FlyTableTheme(
    cellFont: .systemFont(ofSize: NSFont.systemFontSize),
    numericFont: .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
    headerFont: .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold),
    background: .controlBackgroundColor,
    alternateRowBackground: NSColor.alternatingContentBackgroundColors.count > 1 ? NSColor.alternatingContentBackgroundColors[1] : .controlBackgroundColor,
    headerBackground: .controlBackgroundColor,
    headerSortedBackground: nil,
    text: .labelColor,
    secondaryText: .secondaryLabelColor,
    selectedText: .alternateSelectedControlTextColor,
    headerText: .secondaryLabelColor,
    separator: .separatorColor,
    hover: NSColor.labelColor.withAlphaComponent(0.045),
    selectionEmphasized: .selectedContentBackgroundColor,
    selectionUnemphasized: .unemphasizedSelectedContentBackgroundColor,
    selectionEdge: nil,
    cellInset: 8,
    insetStyleMargin: 10,
    selectionCornerRadius: 6,
    cardCornerRadius: 12,
    cardBorder: .separatorColor
  )

  /// FlyUI's default table look, from its semantic tokens (light and dark). Body-compact 14pt
  /// cells, label-strong headings, surface/raised stripes, border-default hairlines, baltic
  /// selection tint with the focus-border edge.
  public static let flyUI: FlyTableTheme = {
    func dynamic(_ name: String, light: (CGFloat, CGFloat, CGFloat), dark: (CGFloat, CGFloat, CGFloat), alpha: CGFloat = 1) -> NSColor {
      NSColor(name: NSColor.Name("FlyTable.\(name)")) { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let c = isDark ? dark : light
        return NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: alpha)
      }
    }
    let surface = dynamic("surface", light: (0.957, 0.961, 0.961), dark: (0.133, 0.125, 0.118))
    let raised = dynamic("surfaceRaised", light: (1, 1, 1), dark: (0.133, 0.125, 0.118))
    let muted = dynamic("surfaceMuted", light: (0.914, 0.933, 0.953), dark: (0.165, 0.157, 0.145))
    let selected = dynamic("surfaceSelected", light: (0.918, 0.965, 0.988), dark: (0.239, 0.176, 0.059))
    let border = dynamic("borderDefault", light: (0.835, 0.875, 0.906), dark: (0.239, 0.224, 0.208))
    let focus = dynamic("borderFocus", light: (0.090, 0.337, 0.463), dark: (0.769, 0.604, 0.271))
    let primary = dynamic("foregroundPrimary", light: (0.106, 0.247, 0.373), dark: (1, 1, 1))
    let secondary = dynamic("foregroundSecondary", light: (0.325, 0.384, 0.451), dark: (0.867, 0.855, 0.827))
    return FlyTableTheme(
      cellFont: .systemFont(ofSize: 14),
      numericFont: .monospacedDigitSystemFont(ofSize: 14, weight: .regular),
      headerFont: .systemFont(ofSize: 14, weight: .semibold),
      background: raised,
      alternateRowBackground: surface,
      headerBackground: raised,
      headerSortedBackground: selected,
      text: primary,
      secondaryText: secondary,
      selectedText: primary,
      headerText: primary,
      separator: border,
      hover: muted,
      selectionEmphasized: selected,
      selectionUnemphasized: muted,
      selectionEdge: focus,
      cellInset: 8,
      insetStyleMargin: 8,
      selectionCornerRadius: 0,
      cardCornerRadius: 12,
      cardBorder: border
    )
  }()

  public init(
    cellFont: NSFont, numericFont: NSFont, headerFont: NSFont, background: NSColor, alternateRowBackground: NSColor,
    headerBackground: NSColor, headerSortedBackground: NSColor?, text: NSColor, secondaryText: NSColor, selectedText: NSColor,
    headerText: NSColor, separator: NSColor, hover: NSColor, selectionEmphasized: NSColor, selectionUnemphasized: NSColor,
    selectionEdge: NSColor?, cellInset: CGFloat, insetStyleMargin: CGFloat, selectionCornerRadius: CGFloat,
    cardCornerRadius: CGFloat, cardBorder: NSColor
  ) {
    self.cellFont = cellFont
    self.numericFont = numericFont
    self.headerFont = headerFont
    self.background = background
    self.alternateRowBackground = alternateRowBackground
    self.headerBackground = headerBackground
    self.headerSortedBackground = headerSortedBackground
    self.text = text
    self.secondaryText = secondaryText
    self.selectedText = selectedText
    self.headerText = headerText
    self.separator = separator
    self.hover = hover
    self.selectionEmphasized = selectionEmphasized
    self.selectionUnemphasized = selectionUnemphasized
    self.selectionEdge = selectionEdge
    self.cellInset = cellInset
    self.insetStyleMargin = insetStyleMargin
    self.selectionCornerRadius = selectionCornerRadius
    self.cardCornerRadius = cardCornerRadius
    self.cardBorder = cardBorder
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
  public var rowHeight: CGFloat?
  public var headerHeight: CGFloat?
  public var showsHeader = true
  public var theme: FlyTableTheme = .system
  public init() {}
}
#endif
