import Foundation

/// A typed cell value. Renderers format lazily and cache the result; the core compares by kind.
public enum FlyCellValue: Sendable, Equatable {
  case text(String)
  case number(Double, fractionDigits: Int = 0)
  case integer(Int)
  case date(Date, style: DateStyle = .short)
  case bool(Bool)
  /// One pill.
  case badge(FlyBadge)
  /// Several pills in a row; the renderer shows as many as fit and a "+N" tail.
  case badges([FlyBadge])
  case empty

  public enum DateStyle: Sendable, Equatable { case short, medium, long, relative }

  public var isNumeric: Bool {
    switch self {
    case .number, .integer: true
    default: false
    }
  }

  /// A human display string. An em dash stands for empty, never "N/A" or "null".
  public func displayString(formatters: FlyCellFormatters = .shared) -> String {
    switch self {
    case .text(let s): s
    case .number(let v, let digits): formatters.number(v, fractionDigits: digits)
    case .integer(let v): formatters.integer(v)
    case .date(let d, let style): formatters.date(d, style: style)
    case .bool(let b): b ? "Yes" : "No"
    case .badge(let b): b.text
    case .badges(let bs): bs.isEmpty ? "—" : bs.map(\.text).joined(separator: ", ")
    case .empty: "—"
    }
  }

  public static func compare(_ a: FlyCellValue, _ b: FlyCellValue) -> ComparisonResult {
    func cmp<T: Comparable>(_ x: T, _ y: T) -> ComparisonResult { x < y ? .orderedAscending : x > y ? .orderedDescending : .orderedSame }
    switch (a, b) {
    case (.empty, .empty): return .orderedSame
    case (.empty, _): return .orderedAscending
    case (_, .empty): return .orderedDescending
    case (.text(let x), .text(let y)): return x.localizedStandardCompare(y)
    case (.number(let x, _), .number(let y, _)): return cmp(x, y)
    case (.integer(let x), .integer(let y)): return cmp(x, y)
    case (.number(let x, _), .integer(let y)): return cmp(x, Double(y))
    case (.integer(let x), .number(let y, _)): return cmp(Double(x), y)
    case (.date(let x, _), .date(let y, _)): return cmp(x, y)
    case (.bool(let x), .bool(let y)): return x == y ? .orderedSame : (x ? .orderedDescending : .orderedAscending)
    case (.badge(let x), .badge(let y)): return x.text.localizedStandardCompare(y.text)
    default: return a.displayString().localizedStandardCompare(b.displayString())
    }
  }
}

/// Shared, locale-aware formatters. Creating formatters per cell is the classic table hot spot.
public final class FlyCellFormatters: @unchecked Sendable {
  public static let shared = FlyCellFormatters()
  private let lock = NSLock()
  private var numberFormatters: [Int: NumberFormatter] = [:]
  private let integerFormatter: NumberFormatter = {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.maximumFractionDigits = 0
    return f
  }()
  private let shortDate: DateFormatter = { let f = DateFormatter(); f.dateStyle = .short; f.timeStyle = .none; return f }()
  private let mediumDate: DateFormatter = { let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .none; return f }()
  private let longDate: DateFormatter = { let f = DateFormatter(); f.dateStyle = .long; f.timeStyle = .none; return f }()
  private let relative = RelativeDateTimeFormatter()

  public func number(_ v: Double, fractionDigits: Int) -> String {
    lock.lock(); defer { lock.unlock() }
    let f: NumberFormatter
    if let cached = numberFormatters[fractionDigits] { f = cached } else {
      f = NumberFormatter()
      f.numberStyle = .decimal
      f.minimumFractionDigits = fractionDigits
      f.maximumFractionDigits = fractionDigits
      numberFormatters[fractionDigits] = f
    }
    return f.string(from: NSNumber(value: v)) ?? String(v)
  }
  public func integer(_ v: Int) -> String {
    lock.lock(); defer { lock.unlock() }
    return integerFormatter.string(from: NSNumber(value: v)) ?? String(v)
  }
  public func date(_ d: Date, style: FlyCellValue.DateStyle) -> String {
    lock.lock(); defer { lock.unlock() }
    switch style {
    case .short: return shortDate.string(from: d)
    case .medium: return mediumDate.string(from: d)
    case .long: return longDate.string(from: d)
    case .relative: return relative.localizedString(for: d, relativeTo: Date())
    }
  }
}

/// Values that can stand in for a cell when sorting a hosted column (`FlyColumn(_:sortBy:content:)`).
public protocol FlyCellValueConvertible {
  var flyCellValue: FlyCellValue { get }
}
extension String: FlyCellValueConvertible { public var flyCellValue: FlyCellValue { .text(self) } }
extension Int: FlyCellValueConvertible { public var flyCellValue: FlyCellValue { .integer(self) } }
extension Double: FlyCellValueConvertible { public var flyCellValue: FlyCellValue { .number(self, fractionDigits: 2) } }
extension Date: FlyCellValueConvertible { public var flyCellValue: FlyCellValue { .date(self) } }
extension Bool: FlyCellValueConvertible { public var flyCellValue: FlyCellValue { .bool(self) } }
extension FlyCellValue: FlyCellValueConvertible { public var flyCellValue: FlyCellValue { self } }
extension Optional: FlyCellValueConvertible where Wrapped: FlyCellValueConvertible {
  public var flyCellValue: FlyCellValue { self?.flyCellValue ?? .empty }
}
