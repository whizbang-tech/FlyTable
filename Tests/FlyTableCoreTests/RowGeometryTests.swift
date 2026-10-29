import Testing
@testable import FlyTableCore

@Suite struct RowGeometryTests {
  @Test func uniformRowsMapOffsetsInConstantTime() {
    let g = FlyRowGeometry(rowCount: 1_000_000, rowHeight: 28)
    #expect(g.contentHeight == 28_000_000)
    #expect(g.row(atY: 0) == 0)
    #expect(g.row(atY: 27.9) == 0)
    #expect(g.row(atY: 28) == 1)
    #expect(g.row(atY: 1e9) == 999_999)
    #expect(g.rows(in: 1000...1500) == 35..<54)
    #expect(g.rows(in: 1000...1500, overscan: 2) == 33..<56)
  }

  @Test func variableRowsUsePrefixSums() {
    let g = FlyRowGeometry(heights: [10, 20, 30, 40], defaultHeight: 20)
    #expect(g.contentHeight == 100)
    #expect(g.minY(ofRow: 2) == 30)
    #expect(g.height(ofRow: 3) == 40)
    #expect(g.row(atY: 29.9) == 1)
    #expect(g.row(atY: 30) == 2)
    #expect(g.rows(in: 15...65) == 1..<4)
  }

  @Test func emptyAndOutOfRangeAreSafe() {
    let empty = FlyRowGeometry(rowCount: 0, rowHeight: 28)
    #expect(empty.rows(in: 0...100).isEmpty)
    let g = FlyRowGeometry(rowCount: 3, rowHeight: 10)
    #expect(g.rows(in: 500...600).isEmpty)
    #expect(g.rows(in: -50 ... -10).isEmpty)
  }

  @Test func densitiesAreOrdered() {
    #expect(FlyRowDensity.compact.rowHeight < FlyRowDensity.comfortable.rowHeight)
    #expect(FlyRowDensity.comfortable.rowHeight < FlyRowDensity.spacious.rowHeight)
  }
}
