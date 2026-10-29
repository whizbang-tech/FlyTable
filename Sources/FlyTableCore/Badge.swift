import Foundation

/// A badge hue. The six tones are FlyUI's semantic tones; the eight named hues are its category
/// colours. Tones resolve to a hue (neutral → graphite, info → azure, success → emerald,
/// warning → amber, destructive → coral, accent → navy).
public enum FlyTint: String, Sendable, Codable, CaseIterable, Hashable {
  case neutral, info, success, warning, destructive, accent
  case azure, navy, cyan, violet, coral, amber, emerald, graphite

  public var hue: FlyTint {
    switch self {
    case .neutral: .graphite
    case .info: .azure
    case .success: .emerald
    case .warning: .amber
    case .destructive: .coral
    case .accent: .navy
    default: self
    }
  }

  /// The hue's ink (dark, for text on a tinted capsule), from FlyUI's category swatches.
  public var swatch: (red: Double, green: Double, blue: Double) {
    switch hue {
    case .azure: (0.00, 0.43, 0.86)
    case .navy: (0.00, 0.34, 0.64)
    case .cyan: (0.05, 0.45, 0.56)
    case .violet: (0.43, 0.16, 0.85)
    case .coral: (0.78, 0.22, 0.23)
    case .amber: (0.71, 0.33, 0.04)
    case .emerald: (0.02, 0.47, 0.34)
    default: (0.29, 0.33, 0.39)
    }
  }

  /// The hue's solid fill (for solid capsules and the tinted capsule's wash), from FlyUI.
  public var solid: (red: Double, green: Double, blue: Double) {
    switch hue {
    case .azure: (0.18, 0.48, 0.98)
    case .navy: (0.00, 0.34, 0.64)
    case .cyan: (0.08, 0.72, 0.86)
    case .violet: (0.52, 0.36, 0.96)
    case .coral: (0.95, 0.36, 0.38)
    case .amber: (0.96, 0.62, 0.12)
    case .emerald: (0.10, 0.68, 0.43)
    default: (0.38, 0.42, 0.48)
    }
  }
}

/// How a badge is filled: FlyUI's tinted status capsule (wash plus edge), solid category capsule,
/// or quiet tag (wash only).
public enum FlyBadgeFill: String, Sendable, Codable, Equatable {
  case tinted, solid, quiet
}

/// A pill drawn inside a cell: text, hue, fill and an optional SF Symbol before the text.
public struct FlyBadge: Sendable, Equatable, Hashable {
  public var text: String
  public var tint: FlyTint
  public var fill: FlyBadgeFill
  public var symbol: String?

  public init(_ text: String, tint: FlyTint = .neutral, fill: FlyBadgeFill = .tinted, symbol: String? = nil) {
    self.text = text
    self.tint = tint
    self.fill = fill
    self.symbol = symbol
  }
}
