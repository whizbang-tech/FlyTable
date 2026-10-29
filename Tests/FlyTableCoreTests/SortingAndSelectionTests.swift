import Testing
import Foundation
@testable import FlyTableCore

@Suite struct SortOrderTests {
  @Test func clickSortsAscendingThenReverses() {
    var order = FlySortOrder()
    order.toggle("name")
    #expect(order.descriptors == [FlySortDescriptor(column: "name", ascending: true)])
    order.toggle("name")
    #expect(order.descriptors == [FlySortDescriptor(column: "name", ascending: false)])
  }

  @Test func clickingAnotherColumnReplacesThePrimary() {
    var order = FlySortOrder([FlySortDescriptor(column: "name")])
    order.toggle("date")
    #expect(order.descriptors == [FlySortDescriptor(column: "date", ascending: true)])
  }

  @Test func shiftClickAppendsSecondaryKeys() {
    var order = FlySortOrder([FlySortDescriptor(column: "name")])
    order.toggle("date", additive: true)
    #expect(order.descriptors.map(\.column) == ["name", "date"])
    order.toggle("date", additive: true)
    #expect(order.descriptors.map(\.ascending) == [true, false])
  }

  @Test func permutationNeverCopiesRowsAndRespectsPriority() {
    let names = ["b", "a", "b", "a"]
    let ages = [1, 2, 0, 3]
    var order = FlySortOrder()
    order.toggle("name")
    order.toggle("age", additive: true)
    let cmp = FlySorter.comparator(order) { column, i, j in
      column == "name" ? FlyCellValue.compare(.text(names[i]), .text(names[j])) : FlyCellValue.compare(.integer(ages[i]), .integer(ages[j]))
    }
    #expect(FlySorter.permutation(count: 4, areInIncreasingOrder: cmp) == [1, 3, 2, 0])
  }
}

@Suite struct SelectionTests {
  let order = [1, 2, 3, 4, 5]

  @Test func clickToggleAndExtend() {
    var s = FlySelection<Int>()
    s.select(2)
    #expect(s.ids == [2] && s.anchor == 2 && s.focused == 2)
    s.toggle(4)
    #expect(s.ids == [2, 4] && s.anchor == 4)
    s.extend(to: 1, in: order)
    #expect(s.ids == [1, 2, 3, 4])
    #expect(s.anchor == 4)
    #expect(s.focused == 1)
  }

  @Test func keyboardTravelClampsAndExtends() {
    var s = FlySelection<Int>()
    s.move(by: 1, in: order, extending: false)
    #expect(s.ids == [1])
    s.move(by: -5, in: order, extending: false)
    #expect(s.ids == [1])
    s.move(by: 2, in: order, extending: true)
    #expect(s.ids == [1, 2, 3])
    s.moveToEdge(true, in: order, extending: false)
    #expect(s.ids == [5])
  }

  @Test func selectAllAndClear() {
    var s = FlySelection<Int>()
    s.selectAll(order)
    #expect(s.ids.count == 5)
    s.clear()
    #expect(s.isEmpty && s.anchor == nil)
  }
}

@Suite struct CellValueTests {
  @Test func displayStringsAreHumane() {
    #expect(FlyCellValue.empty.displayString() == "—")
    #expect(FlyCellValue.bool(true).displayString() == "Yes")
    #expect(FlyCellValue.text("Acme v. Wile").displayString() == "Acme v. Wile")
    #expect(FlyCellValue.number(3.14159, fractionDigits: 2).displayString().hasSuffix("14"))
  }

  @Test func comparisonsAreTypedAndEmptySortsFirst() {
    #expect(FlyCellValue.compare(.integer(2), .number(10, fractionDigits: 0)) == .orderedAscending)
    #expect(FlyCellValue.compare(.text("file10"), .text("file9")) == .orderedDescending)  // localized standard compare
    #expect(FlyCellValue.compare(.empty, .text("a")) == .orderedAscending)
    #expect(FlyCellValue.compare(.bool(false), .bool(true)) == .orderedAscending)
    let d = Date()
    #expect(FlyCellValue.compare(.date(d, style: .short), .date(d.addingTimeInterval(1), style: .short)) == .orderedAscending)
  }
}

@Suite struct CellCacheTests {
  @Test func cachesAndEvictsWholesale() {
    let cache = FlyCellCache<Int>(capacity: 3)
    for i in 0..<3 { _ = cache.value(for: .init(row: i, column: "a", revision: 0)) { i } }
    #expect(cache.count == 3)
    _ = cache.value(for: .init(row: 0, column: "a", revision: 0)) { 99 }
    #expect(cache.hits == 1)
    _ = cache.value(for: .init(row: 9, column: "a", revision: 0)) { 9 }
    #expect(cache.count == 1)  // evicted wholesale, then stored the new one
    _ = cache.value(for: .init(row: 0, column: "a", revision: 1)) { 7 }
    #expect(cache.misses == 5)
  }
}
