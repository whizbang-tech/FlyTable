import Testing
import Foundation
@testable import FlyTableCore

@Suite struct ColumnLayoutTests {
  let specs = [
    FlyColumnSpec(id: "a", title: "A", width: .fixed(100)),
    FlyColumnSpec(id: "b", title: "B", width: .flex(1), minWidth: 50, maxWidth: 150),
    FlyColumnSpec(id: "c", title: "C", width: .flex(2), minWidth: 50),
  ]

  @Test func flexSharesRemainingWidthByWeight() {
    let r = FlyColumnLayoutResolver.resolve(specs: specs, state: .init(), availableWidth: 400)
    #expect(r.map(\.width) == [100, 100, 200])
    #expect(r.map(\.x) == [0, 100, 200])
  }

  @Test func clampedFlexRedistributesToOthers() {
    let r = FlyColumnLayoutResolver.resolve(specs: specs, state: .init(), availableWidth: 1000)
    #expect(r[1].width == 150)   // hit its max
    #expect(r[2].width == 750)   // took the remainder
  }

  @Test func userWidthsAndHiddenColumnsApply() {
    var state = FlyColumnLayoutState()
    state.setWidth(120, for: "b")
    state.toggleHidden("a")
    let r = FlyColumnLayoutResolver.resolve(specs: specs, state: state, availableWidth: 400)
    #expect(r.map(\.id) == ["b", "c"])
    #expect(r[0].width == 120)
    #expect(r[1].width == 280)
  }

  @Test func userOrderAndPinnedLeadingComeFirst() {
    var state = FlyColumnLayoutState()
    state.move("c", before: "a", specs: specs)
    var pinned = specs
    pinned[1].pin = .leading
    let r = FlyColumnLayoutResolver.resolve(specs: pinned, state: state, availableWidth: 400)
    #expect(r.map(\.id) == ["b", "c", "a"])
  }

  @Test func minWidthsForceOverflow() {
    let r = FlyColumnLayoutResolver.resolve(specs: specs, state: .init(), availableWidth: 120)
    #expect(r.last!.maxX == 200)  // 100 fixed + 50 + 50 minimums
  }

  @Test func fitUsesSampledWidth() {
    let s = [FlyColumnSpec(id: "n", title: "N", width: .fit, minWidth: 10), FlyColumnSpec(id: "rest", title: "R")]
    let r = FlyColumnLayoutResolver.resolve(specs: s, state: .init(), availableWidth: 500, fitWidths: ["n": 64])
    #expect(r[0].width == 64)
    #expect(r[1].width == 436)
  }

  @Test func visibleColumnsSliceByRange() {
    let r = FlyColumnLayoutResolver.resolve(specs: specs, state: .init(), availableWidth: 400)
    #expect(FlyColumnLayoutResolver.visibleColumns(r, in: 150...250).map(\.id) == ["b", "c"])
    #expect(FlyColumnLayoutResolver.visibleColumns(r, in: 0...10).map(\.id) == ["a"])
  }

  @Test func layoutStateRoundTripsThroughCodable() throws {
    var state = FlyColumnLayoutState(order: ["c", "a"], widths: ["a": 123], hidden: ["b"])
    state.setWidth(99, for: "c")
    let data = try JSONEncoder().encode(state)
    #expect(try JSONDecoder().decode(FlyColumnLayoutState.self, from: data) == state)
  }
}
