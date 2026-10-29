import Foundation
import FlyTableCore

/// Owns rows, columns, the display permutation, selection and layout state for one table and
/// applies sorting as an index permutation with pre-extracted keys (rows are never copied).
@MainActor
public final class FlyTableEngine<Row: Identifiable> where Row.ID: Hashable & Sendable {
  public private(set) var rows: [Row] = []
  public private(set) var columns: [FlyColumn<Row>] = []
  public private(set) var revision = 0
  public var sortOrder = FlySortOrder() { didSet { if sortOrder != oldValue { resort() } } }
  public var layout = FlyColumnLayoutState()
  public var selection = FlySelection<Row.ID>()
  public private(set) var displayOrder: [Int] = []  // display index -> rows index
  private var displayIDsCache: [Row.ID]?
  private var columnsByID: [FlyColumnID: FlyColumn<Row>] = [:]

  public init() {}

  public var specs: [FlyColumnSpec] { columns.map(\.spec) }
  public var count: Int { displayOrder.count }

  public func setRows(_ rows: [Row], revision: Int) {
    self.rows = rows
    self.revision = revision
    resort()
  }
  public func setColumns(_ columns: [FlyColumn<Row>]) {
    self.columns = columns
    columnsByID = Dictionary(columns.map { ($0.spec.id, $0) }, uniquingKeysWith: { a, _ in a })
    // A sort on a column that no longer exists is dropped.
    sortOrder.descriptors.removeAll { columnsByID[$0.column] == nil }
  }

  public func row(atDisplayIndex i: Int) -> Row { rows[displayOrder[i]] }
  public func id(atDisplayIndex i: Int) -> Row.ID { rows[displayOrder[i]].id }
  public func value(atDisplayIndex i: Int, column: FlyColumnID) -> FlyCellValue {
    columnsByID[column]?.value(rows[displayOrder[i]]) ?? .empty
  }
  public func displayIndex(of id: Row.ID) -> Int? { displayIDs.firstIndex(of: id) }

  /// Identifiers in display order, cached per permutation.
  public var displayIDs: [Row.ID] {
    if let displayIDsCache { return displayIDsCache }
    let ids = displayOrder.map { rows[$0].id }
    displayIDsCache = ids
    return ids
  }

  public func resort() {
    displayIDsCache = nil
    guard !sortOrder.isEmpty, !rows.isEmpty else {
      displayOrder = Array(rows.indices)
      return
    }
    // Pre-extract keys once per descriptor: O(n) closures instead of O(n log n).
    let keys: [[FlyCellValue]] = sortOrder.descriptors.map { d in
      guard let column = columnsByID[d.column] else { return [] }
      return rows.map(column.value)
    }
    let comparator = FlySorter.comparator(sortOrder) { column, a, b in
      guard let i = self.sortOrder.priority(of: column), !keys[i].isEmpty else { return .orderedSame }
      return FlyCellValue.compare(keys[i][a], keys[i][b])
    }
    displayOrder = FlySorter.permutation(count: rows.count, areInIncreasingOrder: comparator)
  }
}
