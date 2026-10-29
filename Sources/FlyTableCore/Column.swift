import Foundation

/// Identifies a column across layout state, sort order and persistence.
public struct FlyColumnID: Hashable, Sendable, Codable, ExpressibleByStringLiteral, CustomStringConvertible {
  public let rawValue: String
  public init(_ rawValue: String) { self.rawValue = rawValue }
  public init(stringLiteral value: String) { self.rawValue = value }
  public var description: String { rawValue }
}

/// How a column takes width. `fixed` never flexes; `flex` shares the remaining width by weight;
/// `fit` asks for the sampled content width and then behaves like `fixed`.
public enum FlyColumnWidth: Sendable, Equatable {
  case fixed(CGFloat)
  case flex(Double = 1)
  case fit
}

/// Text alignment inside a cell. `numeric` is trailing with tabular digits.
public enum FlyColumnAlignment: Sendable, Equatable {
  case leading, center, trailing, numeric
}

/// Whether a column stays put while the table scrolls horizontally.
public enum FlyColumnPin: Sendable, Equatable {
  case none, leading, trailing
}

/// The renderer-independent description of a column.
public struct FlyColumnSpec: Sendable, Identifiable, Equatable {
  public var id: FlyColumnID
  public var title: String
  public var width: FlyColumnWidth
  public var minWidth: CGFloat
  public var maxWidth: CGFloat
  public var alignment: FlyColumnAlignment
  public var pin: FlyColumnPin
  public var isSortable: Bool
  public var isResizable: Bool
  public var isHideable: Bool
  public var isReorderable: Bool

  public init(
    id: FlyColumnID, title: String, width: FlyColumnWidth = .flex(), minWidth: CGFloat = 60,
    maxWidth: CGFloat = 2000, alignment: FlyColumnAlignment = .leading, pin: FlyColumnPin = .none,
    isSortable: Bool = true, isResizable: Bool = true, isHideable: Bool = true, isReorderable: Bool = true
  ) {
    self.id = id
    self.title = title
    self.width = width
    self.minWidth = minWidth
    self.maxWidth = max(maxWidth, minWidth)
    self.alignment = alignment
    self.pin = pin
    self.isSortable = isSortable
    self.isResizable = isResizable
    self.isHideable = isHideable
    self.isReorderable = isReorderable
  }
}
