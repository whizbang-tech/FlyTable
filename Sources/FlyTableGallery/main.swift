import SwiftUI
import FlyTable
import FlyTableCore

struct Matter: Identifiable, Sendable {
  let id: Int
  let title: String
  let client: String
  let attorney: String
  let status: String
  let tags: [String]
  let hours: Double
  let budget: Double
  let opened: Date
  let isBillable: Bool
  var burn: Double { hours / budget }
  var initials: String { attorney.split(separator: " ").compactMap(\.first).map(String.init).joined() }
}

extension Color {
  /// A FlyUI hue as a SwiftUI colour (the gallery has no FlyUI dependency).
  init(_ tint: FlyTint) {
    let c = tint.solid
    self.init(red: c.red, green: c.green, blue: c.blue)
  }
}

/// A hosted cell: initials avatar beside the name. Reads the row state to brighten on emphasis.
struct AttorneyCell: View {
  let matter: Matter
  @Environment(\.flyCellState) private var state

  var body: some View {
    HStack(spacing: 8) {
      Text(matter.initials)
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(.white)
        .frame(width: 20, height: 20)
        .background(Color(SyntheticData.tint(forArea: SyntheticData.practiceAreas[matter.id % SyntheticData.practiceAreas.count])), in: Circle())
      Text(matter.attorney)
        .font(.system(size: 14))
        .lineLimit(1)
        .truncationMode(.tail)
    }
    .opacity(state.isHovered || state.isSelected ? 1 : 0.92)
  }
}

/// A hosted cell: a budget burn bar with the percentage, tinted by how close to budget it is.
struct BurnBar: View {
  let burn: Double

  var body: some View {
    let clamped = min(max(burn, 0), 1.25)
    let tint: FlyTint = burn > 1 ? .destructive : burn > 0.8 ? .warning : .success
    HStack(spacing: 8) {
      GeometryReader { proxy in
        ZStack(alignment: .leading) {
          Capsule().fill(Color(tint).opacity(0.14))
          Capsule().fill(Color(tint)).frame(width: proxy.size.width * min(clamped, 1))
        }
      }
      .frame(height: 6)
      Text(burn, format: .percent.precision(.fractionLength(0)))
        .font(.system(size: 12).monospacedDigit())
        .foregroundStyle(.secondary)
        .frame(width: 40, alignment: .trailing)
    }
  }
}


enum SyntheticData {
  static let firsts = ["Ada", "Grace", "Katherine", "Alan", "Edsger", "Barbara", "Donald", "Margaret", "Linus", "Dennis", "Ken", "Radia", "Frances", "Jean", "Hedy", "Tim"]
  static let lasts = ["Lovelace", "Hopper", "Johnson", "Turing", "Dijkstra", "Liskov", "Knuth", "Hamilton", "Torvalds", "Ritchie", "Thompson", "Perlman", "Allen", "Bartik", "Lamarr", "Berners-Lee"]
  static let parties = ["Acme", "Wile", "Doe", "Roe", "Park Estate", "Smith", "Jones", "Northwind", "Contoso", "Globex", "Initech", "Umbrella", "Stark", "Wayne", "Tyrell", "Hooli"]
  static let statuses = ["Open", "Discovery", "Pending", "On Hold", "Closed", "Appeal"]
  static let practiceAreas = ["Litigation", "Estate", "Family", "Corporate", "IP", "Real Estate", "Employment", "Immigration"]
  static func tint(for status: String) -> FlyTint {
    switch status {
    case "Open": .success
    case "Discovery": .info
    case "Pending": .warning
    case "On Hold": .neutral
    case "Appeal": .destructive
    default: .graphite
    }
  }
  static func tint(forArea area: String) -> FlyTint {
    let hues: [FlyTint] = [.azure, .navy, .cyan, .violet, .coral, .amber, .emerald, .graphite]
    return hues[(practiceAreas.firstIndex(of: area) ?? 0) % hues.count]
  }

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
        tags: (0..<Int(next() % 4)).map { _ in practiceAreas[Int(next() % UInt64(practiceAreas.count))] },
        hours: Double(next() % 40_000) / 100,
        budget: Double(200 + next() % 300),
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
  @State private var flagged: Set<Int> = []

  var body: some View {
    FlyTable(rows, selection: $selection, sortOrder: $sortOrder, layout: $layout) {
      FlyColumn("ID", value: \Matter.id).width(.fit).pinned()
      FlyColumn("Matter", value: \Matter.title).width(.flex(2)).width(min: 160)
      FlyColumn("Client", value: \Matter.client).width(min: 120)
      FlyColumn("Attorney", sortBy: \Matter.attorney) { AttorneyCell(matter: $0) }.width(min: 150)
      FlyColumn("Status", badge: \Matter.status, tint: SyntheticData.tint(for:)).width(.fixed(110))
      FlyColumn("Practice", badges: \Matter.tags, tint: SyntheticData.tint(forArea:)).width(.flex(1.2)).width(min: 140)
      FlyColumn("Hours", value: \Matter.hours).width(.fixed(90))
      FlyColumn("Burn", sortBy: \Matter.burn) { BurnBar(burn: $0.burn) }.width(.fixed(150))
      FlyColumn("Flag") { (matter: Matter) in
        Button {
          if flagged.contains(matter.id) { flagged.remove(matter.id) } else { flagged.insert(matter.id) }
        } label: {
          Image(systemName: flagged.contains(matter.id) ? "star.fill" : "star")
            .foregroundStyle(flagged.contains(matter.id) ? Color(.amber) : .secondary)
        }
        .buttonStyle(.plain)
      }
      .interactive().alignment(.center).width(.fixed(48))
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
        Text("\(selection.count) selected · \(flagged.count) flagged · \(sortOrder.primary.map { "\($0.column) \($0.ascending ? "↑" : "↓")" } ?? "unsorted") · \(lastActivated)")
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
