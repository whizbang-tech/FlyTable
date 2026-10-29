import SwiftUI

/// What the table knows about the row a hosted cell sits in. Read it from the environment
/// (`@Environment(\.flyCellState)`) to adapt a custom cell to selection or hover.
public struct FlyCellState: Equatable, Sendable {
  /// The row is in the selection.
  public var isSelected: Bool
  /// The row is selected and the table is the focused view of the key window.
  public var isEmphasized: Bool
  /// The pointer is over the row.
  public var isHovered: Bool
  /// Position of the row in the current sort order.
  public var displayIndex: Int

  public init(isSelected: Bool = false, isEmphasized: Bool = false, isHovered: Bool = false, displayIndex: Int = 0) {
    self.isSelected = isSelected
    self.isEmphasized = isEmphasized
    self.isHovered = isHovered
    self.displayIndex = displayIndex
  }
}

extension EnvironmentValues {
  /// The state of the row around a hosted cell; the default outside a table is an unselected row.
  @Entry public var flyCellState = FlyCellState()
}
