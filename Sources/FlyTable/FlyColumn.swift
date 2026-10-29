import Foundation
import SwiftUI
import FlyTableCore

/// A column bound to a row type: the renderer-independent spec plus how to read a cell value.
public struct FlyColumn<Row> {
  public var spec: FlyColumnSpec
  public let value: (Row) -> FlyCellValue
  public var cellContent: ((Row) -> AnyView)?
  public var headerContent: (() -> AnyView)?
  public var handlesDoubleClick = false

  public func cellContent<Content: View>(@ViewBuilder _ content: @escaping (Row) -> Content) -> Self {
    var c = self; c.cellContent = { AnyView(content($0)) }; return c
  }
  /// Let hosted cell content own double-click (for example, to begin editing), without row activation.
  public func handlesDoubleClick(_ enabled: Bool = true) -> Self { var c = self; c.handlesDoubleClick = enabled; return c }
  public func headerContent<Content: View>(@ViewBuilder _ content: @escaping () -> Content) -> Self {
    var c = self; c.headerContent = { AnyView(content()) }; return c
  }

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
  public func reorderable(_ flag: Bool) -> Self { var c = self; c.spec.isReorderable = flag; return c }
  public func hideable(_ flag: Bool) -> Self { var c = self; c.spec.isHideable = flag; return c }
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
  public var systemImage: String?
  public var isDestructive: Bool
  public var action: @MainActor @Sendable () -> Void

  public init(_ title: String, isEnabled: Bool = true, systemImage: String? = nil, isDestructive: Bool = false, action: @escaping @MainActor @Sendable () -> Void) {
    self.title = title
    self.isEnabled = isEnabled
    self.isSeparator = false
    self.systemImage = systemImage
    self.isDestructive = isDestructive
    self.action = action
  }
  public static let separator = FlyMenuItem("", isEnabled: false, isSeparator: true) {}
  private init(_ title: String, isEnabled: Bool, isSeparator: Bool, action: @escaping @MainActor @Sendable () -> Void) {
    self.title = title
    self.isEnabled = isEnabled
    self.isSeparator = isSeparator
    self.systemImage = nil
    self.isDestructive = false
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
