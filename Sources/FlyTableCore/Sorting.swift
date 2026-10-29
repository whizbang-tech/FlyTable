import Foundation

public struct FlySortDescriptor: Sendable, Equatable, Codable, Hashable {
  public var column: FlyColumnID
  public var ascending: Bool
  public init(column: FlyColumnID, ascending: Bool = true) {
    self.column = column
    self.ascending = ascending
  }
}

/// Ordered sort keys. Clicking a header makes it primary ascending; clicking again reverses it;
/// Shift-click appends it as a secondary key.
public struct FlySortOrder: Sendable, Equatable, Codable {
  public var descriptors: [FlySortDescriptor]
  public init(_ descriptors: [FlySortDescriptor] = []) { self.descriptors = descriptors }
  public var primary: FlySortDescriptor? { descriptors.first }
  public var isEmpty: Bool { descriptors.isEmpty }

  public func descriptor(for column: FlyColumnID) -> FlySortDescriptor? {
    descriptors.first { $0.column == column }
  }
  public func priority(of column: FlyColumnID) -> Int? {
    descriptors.firstIndex { $0.column == column }
  }

  public mutating func toggle(_ column: FlyColumnID, additive: Bool = false) {
    if let i = descriptors.firstIndex(where: { $0.column == column }) {
      descriptors[i].ascending.toggle()
      if !additive { descriptors = [descriptors[i]] }
    } else {
      let d = FlySortDescriptor(column: column, ascending: true)
      descriptors = additive ? descriptors + [d] : [d]
    }
  }
}

/// Produces an index permutation; rows are never copied.
public enum FlySorter {
  public static func permutation(count: Int, areInIncreasingOrder: (Int, Int) -> Bool) -> [Int] {
    var indexes = Array(0..<count)
    indexes.sort(by: areInIncreasingOrder)
    return indexes
  }

  /// Compose comparators for an ordered list of descriptors into one row-index comparator.
  public static func comparator(
    _ order: FlySortOrder, compare: @escaping (FlyColumnID, Int, Int) -> ComparisonResult
  ) -> (Int, Int) -> Bool {
    let descriptors = order.descriptors
    return { a, b in
      for d in descriptors {
        let r = compare(d.column, a, b)
        if r == .orderedSame { continue }
        return d.ascending ? r == .orderedAscending : r == .orderedDescending
      }
      return false
    }
  }
}
