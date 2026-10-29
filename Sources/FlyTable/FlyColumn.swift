import Foundation
import SwiftUI
import FlyTableCore

/// A column bound to a row type: the renderer-independent spec plus how to read a cell value.
public struct FlyColumn<Row> {
  public var spec: FlyColumnSpec
  /// The cell value: drawn by the renderer for ordinary columns; the sort key for hosted columns.
  public let value: (Row) -> FlyCellValue
  /// A SwiftUI view per row. Hosted cells exist only for the visible rows and are recycled on scroll.
  public internal(set) var content: ((Row) -> AnyView)?
  /// Hosted content receives clicks (buttons, toggles). Otherwise clicks fall through to row selection.
  public internal(set) var isInteractive = false

  public init(_ title: String, id: FlyColumnID? = nil, value: @escaping (Row) -> FlyCellValue) {
    self.spec = FlyColumnSpec(id: id ?? FlyColumnID(title.lowercased()), title: title)
    self.value = value
  }
  public init(_ title: String, id: FlyColumnID? = nil, value: KeyPath<Row, String>) {
    self.init(title, id: id) { .text($0[keyPath: value]) }
  }
  public init(_ title: String, id: FlyColumnID? = nil, value: KeyPath<Row, Int>) {
    self.init(title, id: id) { .integer($0[keyPath: value]) }
    spec.alignment = .numeric
  }
  public init(_ title: String, id: FlyColumnID? = nil, value: KeyPath<Row, Double>, fractionDigits: Int = 2) {
    self.init(title, id: id) { .number($0[keyPath: value], fractionDigits: fractionDigits) }
    spec.alignment = .numeric
  }
  public init(_ title: String, id: FlyColumnID? = nil, value: KeyPath<Row, Date>, style: FlyCellValue.DateStyle = .short) {
    self.init(title, id: id) { .date($0[keyPath: value], style: style) }
  }
  public init(_ title: String, id: FlyColumnID? = nil, value: KeyPath<Row, Bool>) {
    self.init(title, id: id) { .bool($0[keyPath: value]) }
    spec.alignment = .center
  }
  /// A pill per row, tinted by the value (FlyUI status badge).
  public init(
    _ title: String, id: FlyColumnID? = nil, badge: KeyPath<Row, String>, fill: FlyBadgeFill = .tinted,
    symbol: ((String) -> String?)? = nil, tint: @escaping (String) -> FlyTint = { _ in .neutral }
  ) {
    self.init(title, id: id) { row in
      let text = row[keyPath: badge]
      return .badge(FlyBadge(text, tint: tint(text), fill: fill, symbol: symbol?(text)))
    }
  }
  /// Several pills per row (FlyUI category badges or tags).
  public init(
    _ title: String, id: FlyColumnID? = nil, badges: KeyPath<Row, [String]>, fill: FlyBadgeFill = .quiet,
    tint: @escaping (String) -> FlyTint = { _ in .neutral }
  ) {
    self.init(title, id: id) { row in
      .badges(row[keyPath: badges].map { FlyBadge($0, tint: tint($0), fill: fill) })
    }
    spec.isSortable = false
  }

  /// A hosted cell: any SwiftUI view per row, drawn over the row by the renderer for the visible
  /// rows only. Give `sortBy` to make the column sortable; `.fit` width is not measured for
  /// hosted columns, so set a width. Read `@Environment(\.flyCellState)` inside to react to selection.
  ///
  /// ```swift
  /// FlyColumn("Burn", sortBy: \.burn) { matter in BurnBar(matter.burn) }.width(.fixed(140))
  /// ```
  public init<Content: View>(
    _ title: String, id: FlyColumnID? = nil, sortBy: ((Row) -> FlyCellValue)? = nil,
    @ViewBuilder content: @escaping (Row) -> Content
  ) {
    self.spec = FlyColumnSpec(id: id ?? FlyColumnID(title.lowercased()), title: title)
    self.value = sortBy ?? { _ in .empty }
    self.content = { AnyView(content($0)) }
    if sortBy == nil { spec.isSortable = false }
  }
  /// A hosted cell sorted by a key path (String, Int, Double, Date, Bool or an optional of one).
  public init<Content: View, Key: FlyCellValueConvertible>(
    _ title: String, id: FlyColumnID? = nil, sortBy key: KeyPath<Row, Key>, @ViewBuilder content: @escaping (Row) -> Content
  ) {
    self.init(title, id: id, sortBy: { $0[keyPath: key].flyCellValue }, content: content)
  }

  /// Whether the column hosts a SwiftUI view per row.
  public var isHosted: Bool { content != nil }

  public func width(_ width: FlyColumnWidth) -> Self { var c = self; c.spec.width = width; return c }
  public func width(min: CGFloat? = nil, max: CGFloat? = nil) -> Self {
    var c = self
    if let min { c.spec.minWidth = min }
    if let max { c.spec.maxWidth = max }
    return c
  }
  public func alignment(_ alignment: FlyColumnAlignment) -> Self { var c = self; c.spec.alignment = alignment; return c }
  public func pinned(_ pin: FlyColumnPin = .leading) -> Self { var c = self; c.spec.pin = pin; return c }
  public func sortable(_ flag: Bool) -> Self { var c = self; c.spec.isSortable = flag; return c }
  public func resizable(_ flag: Bool) -> Self { var c = self; c.spec.isResizable = flag; return c }
  public func hideable(_ flag: Bool) -> Self { var c = self; c.spec.isHideable = flag; return c }
  /// Let clicks reach hosted content instead of selecting the row. The row is still selected on
  /// mouse-down before the content sees the event.
  public func interactive(_ flag: Bool = true) -> Self { var c = self; c.isInteractive = flag; return c }
}

@resultBuilder
public enum FlyColumnBuilder {
  public static func buildBlock<Row>(_ components: [FlyColumn<Row>]...) -> [FlyColumn<Row>] { components.flatMap { $0 } }
  public static func buildExpression<Row>(_ expression: FlyColumn<Row>) -> [FlyColumn<Row>] { [expression] }
  public static func buildExpression<Row>(_ expression: [FlyColumn<Row>]) -> [FlyColumn<Row>] { expression }
  public static func buildOptional<Row>(_ component: [FlyColumn<Row>]?) -> [FlyColumn<Row>] { component ?? [] }
  public static func buildEither<Row>(first component: [FlyColumn<Row>]) -> [FlyColumn<Row>] { component }
  public static func buildEither<Row>(second component: [FlyColumn<Row>]) -> [FlyColumn<Row>] { component }
  public static func buildArray<Row>(_ components: [[FlyColumn<Row>]]) -> [FlyColumn<Row>] { components.flatMap { $0 } }
}

/// One entry of a table context menu.
public struct FlyMenuItem: Sendable {
  public var title: String
  public var isEnabled: Bool
  public var isSeparator: Bool
  public var action: @MainActor @Sendable () -> Void

  public init(_ title: String, isEnabled: Bool = true, action: @escaping @MainActor @Sendable () -> Void) {
    self.title = title
    self.isEnabled = isEnabled
    self.isSeparator = false
    self.action = action
  }
  public static let separator = FlyMenuItem("", isEnabled: false, isSeparator: true) {}
  private init(_ title: String, isEnabled: Bool, isSeparator: Bool, action: @escaping @MainActor @Sendable () -> Void) {
    self.title = title
    self.isEnabled = isEnabled
    self.isSeparator = isSeparator
    self.action = action
  }
}

/// Visual family. `inset` is the Big Sur look (padded, rounded selection); `fullWidth` is the
/// classic bordered table; `plain` draws no background of its own.
public enum FlyTableStyle: Sendable, Equatable, CaseIterable {
  case inset, fullWidth, plain
  /// FlyUI's card-family surface: a rounded, bordered container with full-width rows inside.
  case card
}
