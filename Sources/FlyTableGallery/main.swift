import SwiftUI
import FlyTable
import FlyTableCore

struct Matter: Identifiable, Sendable {
  let id: Int
  let title: String
  let client: String
  let attorney: String
  let status: String
  let hours: Double
  let opened: Date
  let isBillable: Bool
}

enum SyntheticData {
  static let firsts = ["Ada", "Grace", "Katherine", "Alan", "Edsger", "Barbara", "Donald", "Margaret", "Linus", "Dennis", "Ken", "Radia", "Frances", "Jean", "Hedy", "Tim"]
  static let lasts = ["Lovelace", "Hopper", "Johnson", "Turing", "Dijkstra", "Liskov", "Knuth", "Hamilton", "Torvalds", "Ritchie", "Thompson", "Perlman", "Allen", "Bartik", "Lamarr", "Berners-Lee"]
  static let parties = ["Acme", "Wile", "Doe", "Roe", "Park Estate", "Smith", "Jones", "Northwind", "Contoso", "Globex", "Initech", "Umbrella", "Stark", "Wayne", "Tyrell", "Hooli"]
  static let statuses = ["Open", "Discovery", "Pending", "On Hold", "Closed", "Appeal"]

  static func matters(_ count: Int) -> [Matter] {
    var state: UInt64 = 0x9E3779B97F4A7C15
    func next() -> UInt64 { state = state &* 6364136223846793005 &+ 1442695040888963407; return state >> 33 }
    let base = Date(timeIntervalSince1970: 1_700_000_000)
    var rows: [Matter] = []
    rows.reserveCapacity(count)
    for i in 0..<count {
      let a = Int(next() % UInt64(parties.count)), b = Int(next() % UInt64(parties.count))
      let f = Int(next() % UInt64(firsts.count)), l = Int(next() % UInt64(lasts.count))
      let af = Int(next() % UInt64(firsts.count)), al = Int(next() % UInt64(lasts.count))
      rows.append(Matter(
        id: i,
        title: "\(parties[a]) v. \(parties[b]) \(i + 1)",
        client: "\(firsts[f]) \(lasts[l])",
        attorney: "\(firsts[af]) \(lasts[al])",
        status: statuses[Int(next() % UInt64(statuses.count))],
        hours: Double(next() % 40_000) / 100,
        opened: base.addingTimeInterval(-Double(next() % 2_000) * 86_400),
        isBillable: next() % 4 != 0
      ))
    }
    return rows
  }
}

struct GalleryView: View {
  @State private var rows: [Matter] = SyntheticData.matters(100_000)
  @State private var rowCount = 100_000
  @State private var selection: Set<Int> = []
  @State private var sortOrder = FlySortOrder()
  @State private var layout = FlyColumnLayoutState()
  @State private var style: FlyTableStyle = .card
  @State private var useFlyUITheme = true
  @State private var density: FlyRowDensity = .comfortable
  @State private var alternating = true
  @State private var separators = true
  @State private var lastActivated = "—"

  var body: some View {
    FlyTable(rows, selection: $selection, sortOrder: $sortOrder, layout: $layout) {
      FlyColumn("ID", value: \Matter.id).width(.fit).pinned()
      FlyColumn("Matter", value: \Matter.title).width(.flex(2)).width(min: 160)
      FlyColumn("Client", value: \Matter.client).width(min: 120)
      FlyColumn("Attorney", value: \Matter.attorney).width(min: 120)
      FlyColumn("Status", value: \Matter.status).width(.fixed(100))
      FlyColumn("Hours", value: \Matter.hours).width(.fixed(90))
      FlyColumn("Opened", value: \Matter.opened).width(.fixed(110))
      FlyColumn("Billable", value: \Matter.isBillable).width(.fixed(80))
    }
    .tableStyle(style)
    .theme(useFlyUITheme ? .flyUI : .system)
    .density(density)
    .alternatingRowBackgrounds(alternating)
    .rowSeparators(separators)
    .onRowActivate { ids in lastActivated = "\(ids.count) row(s)" }
    .contextMenu { ids in
      [
        FlyMenuItem("Open \(ids.count) Matter\(ids.count == 1 ? "" : "s")") { lastActivated = "menu: \(ids.count)" },
        .separator,
        FlyMenuItem("Copy", isEnabled: !ids.isEmpty) {},
      ]
    }
    .padding(16)
    .background(Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(srgbRed: 0.09, green: 0.085, blue: 0.08, alpha: 1) : NSColor(srgbRed: 0.957, green: 0.961, blue: 0.961, alpha: 1) }))
    .frame(minWidth: 900, minHeight: 500)
    .toolbar {
      ToolbarItemGroup {
        Picker("Rows", selection: $rowCount) {
          Text("1,000").tag(1_000)
          Text("100,000").tag(100_000)
          Text("1,000,000").tag(1_000_000)
        }
        .onChange(of: rowCount) { _, n in rows = SyntheticData.matters(n); selection = [] }
        Picker("Style", selection: $style) {
          Text("Inset").tag(FlyTableStyle.inset)
          Text("Full Width").tag(FlyTableStyle.fullWidth)
          Text("Plain").tag(FlyTableStyle.plain)
          Text("Card").tag(FlyTableStyle.card)
        }
        Toggle("FlyUI", isOn: $useFlyUITheme)
        Picker("Density", selection: $density) {
          ForEach(FlyRowDensity.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
        }
        Toggle("Alternating", isOn: $alternating)
        Toggle("Separators", isOn: $separators)
        Text("\(selection.count) selected · \(sortOrder.primary.map { "\($0.column) \($0.ascending ? "↑" : "↓")" } ?? "unsorted") · \(lastActivated)")
          .font(.caption).foregroundStyle(.secondary)
      }
    }
  }
}

struct GalleryApp: App {
  init() {
    NSApplication.shared.setActivationPolicy(.regular)
    NSApplication.shared.activate(ignoringOtherApps: true)
  }
  var body: some Scene {
    WindowGroup("FlyTable Gallery") { GalleryView() }
  }
}

GalleryApp.main()
