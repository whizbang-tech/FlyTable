import Foundation

/// Row heights by density. Header height always equals row height.
public enum FlyRowDensity: String, Sendable, CaseIterable, Codable {
  case compact, comfortable, spacious
  public var rowHeight: CGFloat {
    switch self {
    case .compact: 24
    case .comfortable: 28
    case .spacious: 36
    }
  }
}

/// Maps between content offsets and row indexes. Fixed-height rows are O(1); variable heights
/// use prefix sums with binary search (O(log n)).
public struct FlyRowGeometry: Sendable, Equatable {
  public private(set) var rowCount: Int
  public private(set) var defaultHeight: CGFloat
  private var prefix: [CGFloat]?  // prefix[i] = y of row i; prefix[count] = total. nil when uniform.

  public init(rowCount: Int, rowHeight: CGFloat) {
    self.rowCount = max(rowCount, 0)
    self.defaultHeight = rowHeight
    self.prefix = nil
  }

  public init(heights: [CGFloat], defaultHeight: CGFloat) {
    self.rowCount = heights.count
    self.defaultHeight = defaultHeight
    var p: [CGFloat] = [0]
    p.reserveCapacity(heights.count + 1)
    for h in heights { p.append(p[p.count - 1] + h) }
    self.prefix = p
  }

  public var isUniform: Bool { prefix == nil }
  public var contentHeight: CGFloat { prefix?.last ?? CGFloat(rowCount) * defaultHeight }

  public func minY(ofRow row: Int) -> CGFloat {
    if let prefix { return prefix[min(max(row, 0), rowCount)] }
    return CGFloat(row) * defaultHeight
  }
  public func height(ofRow row: Int) -> CGFloat {
    if let prefix { return prefix[row + 1] - prefix[row] }
    return defaultHeight
  }

  /// The row containing `y`, clamped to the valid range.
  public func row(atY y: CGFloat) -> Int {
    guard rowCount > 0 else { return 0 }
    if let prefix {
      var lo = 0, hi = rowCount - 1
      while lo < hi {
        let mid = (lo + hi + 1) / 2
        if prefix[mid] <= y { lo = mid } else { hi = mid - 1 }
      }
      return lo
    }
    return min(max(Int((y / defaultHeight).rounded(.down)), 0), rowCount - 1)
  }

  /// Rows intersecting a vertical range plus `overscan` rows on each side.
  public func rows(in range: ClosedRange<CGFloat>, overscan: Int = 0) -> Range<Int> {
    guard rowCount > 0, range.upperBound >= 0, range.lowerBound <= contentHeight else { return 0..<0 }
    let first = max(row(atY: max(range.lowerBound, 0)) - overscan, 0)
    let last = min(row(atY: range.upperBound) + overscan, rowCount - 1)
    return first..<(last + 1)
  }
}
