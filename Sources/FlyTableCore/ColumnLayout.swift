import Foundation

/// User-owned column layout: order, explicit widths and hidden columns. Codable so the host can
/// persist it per table. Columns absent from `order` append in declaration order.
public struct FlyColumnLayoutState: Sendable, Codable, Equatable {
  public var order: [FlyColumnID]
  public var widths: [FlyColumnID: CGFloat]
  public var hidden: Set<FlyColumnID>

  public init(order: [FlyColumnID] = [], widths: [FlyColumnID: CGFloat] = [:], hidden: Set<FlyColumnID> = []) {
    self.order = order
    self.widths = widths
    self.hidden = hidden
  }

  public mutating func setWidth(_ width: CGFloat, for id: FlyColumnID) { widths[id] = width }
  public mutating func toggleHidden(_ id: FlyColumnID) {
    if hidden.contains(id) { hidden.remove(id) } else { hidden.insert(id) }
  }
  public mutating func move(_ id: FlyColumnID, before target: FlyColumnID?, specs: [FlyColumnSpec]) {
    var ids = orderedIDs(specs: specs)
    guard let from = ids.firstIndex(of: id) else { return }
    ids.remove(at: from)
    if let target, let to = ids.firstIndex(of: target) { ids.insert(id, at: to) } else { ids.append(id) }
    order = ids
  }

  /// Declared order with the user's order applied first.
  public func orderedIDs(specs: [FlyColumnSpec]) -> [FlyColumnID] {
    let declared = specs.map(\.id)
    let known = Set(declared)
    var result = order.filter { known.contains($0) }
    for id in declared where !result.contains(id) { result.append(id) }
    return result
  }
}

/// A column with its resolved horizontal frame in content coordinates.
public struct FlyResolvedColumn: Sendable, Equatable, Identifiable {
  public var id: FlyColumnID
  public var spec: FlyColumnSpec
  public var x: CGFloat
  public var width: CGFloat
  public var maxX: CGFloat { x + width }
  public init(spec: FlyColumnSpec, x: CGFloat, width: CGFloat) {
    self.id = spec.id
    self.spec = spec
    self.x = x
    self.width = width
  }
}

/// Resolves column widths the way NSTableView's `uniform` autoresizing and CSS grid's `fr` do:
/// fixed and user-sized columns keep their width, flex columns share what is left by weight,
/// every width is clamped to its column's limits, and the remainder is redistributed until stable.
public enum FlyColumnLayoutResolver {
  public static func resolve(
    specs: [FlyColumnSpec], state: FlyColumnLayoutState, availableWidth: CGFloat,
    fitWidths: [FlyColumnID: CGFloat] = [:]
  ) -> [FlyResolvedColumn] {
    let byID = Dictionary(uniqueKeysWithValues: specs.map { ($0.id, $0) })
    let visible = state.orderedIDs(specs: specs).compactMap { byID[$0] }.filter { !state.hidden.contains($0.id) }
    guard !visible.isEmpty else { return [] }

    // Pinned leading columns first, then unpinned, then pinned trailing.
    let ordered = visible.filter { $0.pin == .leading } + visible.filter { $0.pin == .none } + visible.filter { $0.pin == .trailing }

    var widths: [FlyColumnID: CGFloat] = [:]
    var flex: [(FlyColumnSpec, Double)] = []
    for spec in ordered {
      if let user = state.widths[spec.id] {
        widths[spec.id] = clamp(user, spec)
      } else {
        switch spec.width {
        case .fixed(let w): widths[spec.id] = clamp(w, spec)
        case .fit: widths[spec.id] = clamp(fitWidths[spec.id] ?? spec.minWidth, spec)
        case .flex(let weight): flex.append((spec, max(weight, 0.0001)))
        }
      }
    }

    let fixedTotal = widths.values.reduce(0, +)
    var remaining = max(availableWidth - fixedTotal, 0)
    var pending = flex
    // Iterate: assign by weight, pin any column that hit a limit, redistribute the rest.
    while !pending.isEmpty {
      let totalWeight = pending.reduce(0) { $0 + $1.1 }
      var pinned: [(FlyColumnSpec, Double)] = []
      var next: [(FlyColumnSpec, Double)] = []
      for (spec, weight) in pending {
        let proposed = remaining * CGFloat(weight / totalWeight)
        let clamped = clamp(proposed, spec)
        if clamped != proposed { pinned.append((spec, weight)); widths[spec.id] = clamped } else { next.append((spec, weight)) }
      }
      if pinned.isEmpty {
        for (spec, weight) in next { widths[spec.id] = remaining * CGFloat(weight / totalWeight) }
        break
      }
      remaining = max(remaining - pinned.reduce(0) { $0 + widths[$1.0.id]! }, 0)
      pending = next
    }

    var x: CGFloat = 0
    var result: [FlyResolvedColumn] = []
    for spec in ordered {
      let w = (widths[spec.id] ?? spec.minWidth).rounded(.down)
      result.append(FlyResolvedColumn(spec: spec, x: x, width: w))
      x += w
    }
    return result
  }

  private static func clamp(_ w: CGFloat, _ spec: FlyColumnSpec) -> CGFloat {
    min(max(w, spec.minWidth), spec.maxWidth)
  }

  /// Which resolved columns intersect a horizontal range: the renderer draws only these.
  public static func visibleColumns(_ columns: [FlyResolvedColumn], in range: ClosedRange<CGFloat>) -> ArraySlice<FlyResolvedColumn> {
    guard !columns.isEmpty else { return [] }
    let first = columns.firstIndex { $0.maxX >= range.lowerBound } ?? columns.endIndex
    let last = columns.lastIndex { $0.x <= range.upperBound } ?? columns.startIndex
    return first <= last ? columns[first...last] : []
  }
}
