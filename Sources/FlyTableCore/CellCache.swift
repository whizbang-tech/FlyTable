import Foundation

/// Key for one rendered cell: display index, column, and the data revision that produced it.
public struct FlyCellKey: Hashable, Sendable {
  public var row: Int
  public var column: FlyColumnID
  public var revision: Int
  public init(row: Int, column: FlyColumnID, revision: Int) {
    self.row = row
    self.column = column
    self.revision = revision
  }
}

/// A bounded cache for shaped cell content (Core Text lines on AppKit). Eviction is wholesale
/// once the cap is exceeded: cheap, and a scroll window refills within one frame.
public final class FlyCellCache<Value> {
  private var storage: [FlyCellKey: Value] = [:]
  public let capacity: Int
  public private(set) var hits = 0
  public private(set) var misses = 0

  public init(capacity: Int = 20_000) { self.capacity = capacity }

  public func value(for key: FlyCellKey, make: () -> Value) -> Value {
    if let v = storage[key] { hits += 1; return v }
    misses += 1
    if storage.count >= capacity { storage.removeAll(keepingCapacity: true) }
    let v = make()
    storage[key] = v
    return v
  }
  public func removeAll() { storage.removeAll(keepingCapacity: true) }
  public var count: Int { storage.count }
}
