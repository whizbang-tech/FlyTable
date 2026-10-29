import Testing
import Foundation
import SwiftUI
#if os(macOS)
import AppKit
#endif
import FlyTableCore
@testable import FlyTable

@Suite @MainActor struct ConsumerCapabilityTests {
  struct Row: Identifiable { let id: Int; let name: String }

  @Test func externalSortingPreservesProvidedOrderAndSortIndicators() {
    let engine = FlyTableEngine<Row>()
    engine.setColumns([FlyColumn("Name", id: "name", value: \.name)])
    engine.setRows([Row(id: 1, name: "Z"), Row(id: 2, name: "A")], revision: 1)
    engine.sortOrder = FlySortOrder([FlySortDescriptor(column: "name")])
    #expect(engine.displayIDs == [2, 1])
    engine.sortsRows = false
    #expect(engine.displayIDs == [1, 2])
    #expect(engine.sortOrder.primary?.column == "name")
    engine.setRows([Row(id: 3, name: "Y"), Row(id: 4, name: "B")], revision: 2)
    #expect(engine.displayIDs == [3, 4])
    engine.sortsRows = true
    #expect(engine.displayIDs == [4, 3])
  }

  @Test func revisionRefreshesSameCountAndIdentityValues() {
    let engine = FlyTableEngine<Row>()
    engine.setColumns([FlyColumn("Name", id: "name", value: \.name)])
    engine.setRows([Row(id: 1, name: "Before")], revision: 1)
    engine.setRows([Row(id: 1, name: "After")], revision: 2)
    #expect(engine.value(atDisplayIndex: 0, column: "name").displayString() == "After")
  }

  @Test func hostedContentRemainsOptionalAndDoesNotReplaceSortValues() {
    let plain = FlyColumn<Row>("Name", value: \.name)
    #expect(plain.cellContent == nil)
    #expect(plain.headerContent == nil)
    let custom = plain.cellContent { Text($0.name) }.headerContent { Text("Select") }.reorderable(false)
    #expect(custom.cellContent != nil)
    #expect(custom.headerContent != nil)
    #expect(custom.value(Row(id: 1, name: "Value")).displayString() == "Value")
    #expect(!custom.spec.isReorderable)
  }
  #if os(macOS)
  @Test func hostedCellsStayBoundedToVisibleRowsWhileScrolling() {
    let engine = FlyTableEngine<Row>()
    engine.setColumns([FlyColumn<Row>("Name", value: \.name).cellContent { Text($0.name) }])
    engine.setRows((0..<1_000).map { Row(id: $0, name: "Row \($0)") }, revision: 1)
    let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 600, height: 200))
    let view = FlyTableDocumentView(engine: engine)
    scroll.documentView = view
    view.relayout()
    #expect(!view.subviews.isEmpty)
    #expect(view.subviews.count < 20)
    scroll.contentView.scroll(to: NSPoint(x: 0, y: 2_800))
    view.updateHostedContent()
    #expect(!view.subviews.isEmpty)
    #expect(view.subviews.count < 20)
    #expect(view.subviews.allSatisfy { $0.frame.minY >= 2_800 })
  }

  @Test func variableRowGeometryPreservesSupplementaryHeight() {
    let engine = FlyTableEngine<Row>()
    engine.setColumns([FlyColumn("Name", value: \.name)])
    engine.setRows([Row(id: 1, name: "Group"), Row(id: 2, name: "Record"), Row(id: 3, name: "Detail")], revision: 1)
    let view = FlyTableDocumentView(engine: engine)
    view.rowHeightProvider = { $0.id == 3 ? 120 : 28 }
    view.relayout()
    #expect(view.rowRect(0).height == 28)
    #expect(view.rowRect(2).height == 120)
    #expect(view.rowRect(2).minY == view.headerHeight + 56)
  }
  @Test func accessibilityIsBoundedAndExposesSelectionDisabledStateAndActivation() {
    let engine = FlyTableEngine<Row>()
    engine.setColumns([FlyColumn("Name", value: \.name)])
    engine.setRows((0..<100_000).map { Row(id: $0, name: "Row \($0)") }, revision: 1)
    let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 600, height: 200))
    let view = FlyTableDocumentView(engine: engine)
    scroll.documentView = view
    view.disabledIDs = [1]
    view.relayout()
    var activated: Set<Int> = []
    view.onActivate = { activated = $0 }
    let rows = view.accessibilityRows()!.compactMap { $0 as? NSAccessibilityElement }
    #expect(view.accessibilityRowCount() == 100_000)
    #expect(rows.count < 20)
    #expect(rows[0].accessibilityLabel() == "Row 0")
    #expect(!rows[1].isAccessibilityEnabled())
    #expect(!rows[1].accessibilityPerformPress())
    #expect(rows[0].accessibilityPerformPress())
    #expect(activated == [0])
    #expect(engine.selection.ids == [0])
    #expect(view.accessibilitySelectedRows()?.count == 1)
    engine.selection.focused = 99_999
    #expect(view.accessibilityRows()!.count < 20)
    let accessibleIndexes = view.accessibilityRows()!.compactMap { ($0 as? NSAccessibilityElement)?.accessibilityIndex() }
    #expect(accessibleIndexes.contains(99_999))
  }

  @Test func optionalSoleSelectionToggleDoesNotBreakRangeOrDoubleClick() {
    let engine = FlyTableEngine<Row>()
    engine.setRows((0..<4).map { Row(id: $0, name: "Row \($0)") }, revision: 1)
    let view = FlyTableDocumentView(engine: engine)
    view.frame = NSRect(x: 0, y: 0, width: 500, height: 200)
    view.togglesSoleSelection = true
    view.relayout()
    func click(_ index: Int, flags: NSEvent.ModifierFlags = [], count: Int = 1) {
      let rect = view.rowRect(index)
      let location = view.convert(NSPoint(x: 10, y: rect.midY), to: nil)
      let event = NSEvent.mouseEvent(with: .leftMouseDown, location: location, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: count, pressure: 1)!
      view.mouseDown(with: event)
    }
    click(0)
    #expect(engine.selection.ids == [0])
    click(0)
    #expect(engine.selection.ids.isEmpty)
    var activated: Set<Int> = []
    view.onActivate = { activated = $0 }
    click(0, count: 2)
    #expect(engine.selection.ids == [0])
    #expect(activated == [0])
    click(3, flags: .shift)
    #expect(engine.selection.ids == [0, 1, 2, 3])
    view.togglesSelection = true
    click(1)
    #expect(engine.selection.ids == [0, 2, 3])
    click(1)
    #expect(engine.selection.ids == [0, 1, 2, 3])
  }

  @Test func intrinsicHostedCellHeightExpandsRowGeometry() {
    let engine = FlyTableEngine<Row>()
    engine.setColumns([FlyColumn<Row>("Name", value: \.name).cellContent { _ in VStack { Text("Identity").font(.system(size: 22)); Text("Second line").font(.system(size: 22)) } }])
    engine.setRows([Row(id: 1, name: "Tall")], revision: 1)
    let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 600, height: 200))
    let view = FlyTableDocumentView(engine: engine)
    scroll.documentView = view
    view.relayout()
    view.relayout()
    #expect(view.rowRect(0).height > view.rowHeight)
    let cellHeight = view.rowRect(0).height
    view.rowContentProvider = { _ in AnyView(VStack { Text("Detail").font(.system(size: 28)); Text("Expanded details").font(.system(size: 28)); Text("Third line").font(.system(size: 28)) }) }
    view.relayout()
    view.relayout()
    #expect(view.rowRect(0).height > cellHeight)
  }

  @Test func scrollEndDeduplicatesGeometryButReportsChangedShortContent() async {
    let engine = FlyTableEngine<Row>()
    engine.setRows([Row(id: 1, name: "One")], revision: 1)
    let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 600, height: 200))
    let view = FlyTableDocumentView(engine: engine)
    scroll.documentView = view
    var reports = 0
    view.onScrollEndVisible = { reports += 1 }
    view.relayout()
    await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
    #expect(reports == 1)
    view.relayout()
    await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
    #expect(reports == 1)
    engine.setRows([Row(id: 1, name: "One"), Row(id: 2, name: "Two")], revision: 2)
    view.relayout()
    await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
    #expect(reports == 2)
  }

  @Test func optionalHeaderHeightAndSortingAdmissionPreserveColumnCommands() {
    let engine = FlyTableEngine<Row>()
    engine.setColumns([FlyColumn("Name", id: "name", value: \.name), FlyColumn("Other", id: "other", value: \.name)])
    engine.setRows([Row(id: 1, name: "One")], revision: 1)
    engine.sortOrder = FlySortOrder([FlySortDescriptor(column: "other")])
    let view = FlyTableDocumentView(engine: engine)
    view.frame = NSRect(x: 0, y: 0, width: 600, height: 200)
    view.configuration.headerHeight = 72
    view.allowsMultiColumnSorting = false
    view.relayout()
    #expect(view.rowRect(0).minY == 72)
    let location = view.convert(NSPoint(x: 20, y: 20), to: nil)
    func event(_ type: NSEvent.EventType) -> NSEvent {
      NSEvent.mouseEvent(with: type, location: location, modifierFlags: [.shift], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }
    view.mouseDown(with: event(.leftMouseDown))
    view.mouseUp(with: event(.leftMouseUp))
    #expect(engine.sortOrder == FlySortOrder([FlySortDescriptor(column: "name")]))
    var menuColumn: FlyColumnID?
    view.columnContextMenu = { menuColumn = $0; return [FlyMenuItem("Custom command") {}] }
    let menu = view.menu(for: event(.rightMouseDown))
    #expect(menuColumn == "name")
    #expect(menu?.items.first?.title == "Custom command")
    view.keyboardNavigationEnabled = false
    view.selectAll(nil)
    #expect(engine.selection.ids.isEmpty)
  }

  @Test func nativeContextMenuPreservesOptionalIconsAndDestructiveAppearance() {
    let engine = FlyTableEngine<Row>()
    engine.setColumns([FlyColumn("Name", id: "name", value: \.name)])
    engine.setRows([Row(id: 1, name: "One")], revision: 1)
    let view = FlyTableDocumentView(engine: engine)
    view.frame = NSRect(x: 0, y: 0, width: 600, height: 200)
    view.relayout()
    view.rowContextMenu = { _, _ in [
      FlyMenuItem("Remove", systemImage: "trash", isDestructive: true) {},
      FlyMenuItem("Unavailable", isEnabled: false, systemImage: "trash", isDestructive: true) {},
      FlyMenuItem("Standard") {},
    ] }
    let location = view.convert(NSPoint(x: 20, y: view.rowRect(0).midY), to: nil)
    let event = NSEvent.mouseEvent(with: .rightMouseDown, location: location, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    let items = view.menu(for: event)!.items
    #expect(items[0].title == "Remove")
    #expect(items[0].image != nil)
    #expect(items[0].attributedTitle?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == .systemRed)
    #expect(!items[1].isEnabled)
    #expect(items[1].attributedTitle == nil)
    #expect(items[2].image == nil && items[2].attributedTitle == nil)
    #expect(FlyMenuItem.separator.systemImage == nil && !FlyMenuItem.separator.isDestructive)
  }

  @Test func editableCellDoubleClickDoesNotActivateRow() {
    let engine = FlyTableEngine<Row>()
    engine.setColumns([FlyColumn<Row>("Name", value: \.name).handlesDoubleClick().cellContent { Text($0.name) }])
    engine.setRows([Row(id: 1, name: "One")], revision: 1)
    let view = FlyTableDocumentView(engine: engine)
    view.frame = NSRect(x: 0, y: 0, width: 600, height: 200)
    view.relayout()
    var activations = 0
    view.onActivate = { _ in activations += 1 }
    let location = view.convert(NSPoint(x: 20, y: view.rowRect(0).midY), to: nil)
    func click(_ count: Int) {
      view.mouseDown(with: NSEvent.mouseEvent(with: .leftMouseDown, location: location, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: count, pressure: 1)!)
    }
    click(1)
    #expect(engine.selection.ids == [1])
    click(2)
    #expect(activations == 0)
    #expect(engine.selection.focused == 1)
    engine.setColumns([FlyColumn<Row>("Name", value: \.name)])
    click(2)
    #expect(activations == 1)
  }

  @Test func commandReturnUsesFocusedRowWithoutRequiringSelection() {
    let engine = FlyTableEngine<Row>()
    engine.setRows([Row(id: 1, name: "One"), Row(id: 2, name: "Two")], revision: 1)
    let view = FlyTableDocumentView(engine: engine)
    view.selectionMode = .none
    view.focusedActivationOnly = true
    engine.selection.focused = 2
    var opened: Set<Int> = []
    view.onOpenInNewTab = { opened = $0 }
    let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command], timestamp: 0, windowNumber: 0, context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)!
    view.keyDown(with: event)
    #expect(opened == [2])
  }
  #endif

}
