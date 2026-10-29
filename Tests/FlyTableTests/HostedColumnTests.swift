import Testing
import SwiftUI
import FlyTableCore
@testable import FlyTable

@Suite struct HostedColumnTests {
  struct Row: Identifiable { let id: Int; let name: String; let score: Double?; let flag: Bool }
  let row = Row(id: 1, name: "Ada", score: 0.5, flag: true)

  @Test func hostedColumnWithoutSortKeyIsNotSortable() {
    let column = FlyColumn<Row>("Avatar") { Text($0.name) }
    #expect(column.isHosted)
    #expect(!column.spec.isSortable)
    #expect(!column.isInteractive)
    #expect(column.value(row) == .empty)
  }

  @Test func hostedColumnSortsByKeyPath() {
    let byName = FlyColumn<Row>("Name", sortBy: \.name) { Text($0.name) }
    #expect(byName.spec.isSortable)
    #expect(byName.value(row) == .text("Ada"))
    let byScore = FlyColumn<Row>("Score", sortBy: \.score) { Text("\($0.score ?? 0)") }
    #expect(byScore.value(row) == .number(0.5, fractionDigits: 2))
    #expect(byScore.value(Row(id: 2, name: "B", score: nil, flag: false)) == .empty)
    let byFlag = FlyColumn<Row>("Flag", sortBy: { .bool($0.flag) }) { _ in Text("") }
    #expect(byFlag.value(row) == .bool(true))
  }

  @Test func interactiveModifierAndIdentifier() {
    let column = FlyColumn<Row>("Open", id: "open-action") { _ in Button("Open") {} }.interactive()
    #expect(column.isInteractive)
    #expect(column.spec.id == "open-action")
    #expect(column.spec.title == "Open")
  }

  @Test func ordinaryColumnsAreNotHosted() {
    let column = FlyColumn<Row>("Name", value: \.name)
    #expect(!column.isHosted)
    #expect(column.content == nil)
  }

  @Test func cellValueConvertibleCoversTheKeyTypes() {
    #expect("x".flyCellValue == .text("x"))
    #expect(3.flyCellValue == .integer(3))
    #expect(true.flyCellValue == .bool(true))
    let date = Date(timeIntervalSince1970: 0)
    #expect(date.flyCellValue == .date(date))
    #expect(FlyCellValue.empty.flyCellValue == .empty)
    let none: String? = nil
    #expect(none.flyCellValue == .empty)
  }

  @MainActor @Test func engineSortsHostedColumnByItsKey() {
    let engine = FlyTableEngine<Row>()
    engine.setColumns([FlyColumn<Row>("Name", sortBy: \.name) { Text($0.name) }])
    engine.setRows([Row(id: 1, name: "Zed", score: nil, flag: false), Row(id: 2, name: "Ada", score: nil, flag: false)], revision: 0)
    engine.sortOrder.toggle("name", additive: false)
    #expect(engine.displayIDs == [2, 1])
  }
}
