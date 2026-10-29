import Foundation

/// Row selection with an anchor for Shift-extension and a focused row for keyboard travel.
/// Selection is kept by identifier so it survives sorting and filtering.
public struct FlySelection<ID: Hashable & Sendable>: Sendable, Equatable {
  public var ids: Set<ID>
  public var anchor: ID?
  public var focused: ID?

  public init(ids: Set<ID> = [], anchor: ID? = nil, focused: ID? = nil) {
    self.ids = ids
    self.anchor = anchor
    self.focused = focused
  }

  public var isEmpty: Bool { ids.isEmpty }

  public mutating func select(_ id: ID) {
    ids = [id]
    anchor = id
    focused = id
  }
  public mutating func toggle(_ id: ID) {
    if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
    anchor = id
    focused = id
  }
  /// Shift-click or Shift-arrow: select every row between the anchor and `id` in display order.
  public mutating func extend(to id: ID, in order: [ID]) {
    guard let anchor, let a = order.firstIndex(of: anchor), let b = order.firstIndex(of: id) else {
      select(id); return
    }
    ids = Set(order[min(a, b)...max(a, b)])
    focused = id
  }
  public mutating func selectAll(_ order: [ID]) {
    ids = Set(order)
    if anchor == nil { anchor = order.first }
  }
  public mutating func clear() {
    ids = []
    anchor = nil
  }
  /// Keyboard travel: move focus by `delta` in display order; extend with Shift, else select.
  public mutating func move(by delta: Int, in order: [ID], extending: Bool) {
    guard !order.isEmpty else { return }
    let current = focused.flatMap { order.firstIndex(of: $0) } ?? (delta > 0 ? -1 : order.count)
    let next = min(max(current + delta, 0), order.count - 1)
    let id = order[next]
    if extending { extend(to: id, in: order) } else { select(id) }
  }
  public mutating func moveToEdge(_ toEnd: Bool, in order: [ID], extending: Bool) {
    guard let id = toEnd ? order.last : order.first else { return }
    if extending { extend(to: id, in: order) } else { select(id) }
  }
}
