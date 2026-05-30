import AppKit

extension NSColor {
    /// Builds an sRGB color from a `#RRGGBB` (or `RRGGBB`) string. Returns nil
    /// for malformed input so callers can fall back to a semantic color.
    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = Int(s, radix: 16) else { return nil }
        let r = CGFloat((v >> 16) & 0xFF) / 255
        let g = CGFloat((v >> 8) & 0xFF) / 255
        let b = CGFloat(v & 0xFF) / 255
        self.init(srgbRed: r, green: g, blue: b, alpha: 1)
    }

    /// Uppercase `#RRGGBB` of the color resolved into sRGB.
    var hexString: String {
        let c = usingColorSpace(.sRGB) ?? self
        let r = Int((c.redComponent * 255).rounded())
        let g = Int((c.greenComponent * 255).rounded())
        let b = Int((c.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

/// How many distinct heading colors are in play.
enum Coloring: String, CaseIterable, Codable {
    case off, unified, standard

    var displayName: String {
        switch self {
        case .off: return "Default"
        case .unified: return "Unified"
        case .standard: return "Standard"
        }
    }
}

/// The window appearance Mode.
enum AppAppearance: String, CaseIterable, Codable {
    case system, light, dark

    /// The forced appearance, or nil to follow the OS (System).
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

/// One heading slot's color as a tuned light/dark hex pair. Persisted as hex
/// strings; resolved to a dynamic `NSColor` that follows the effective
/// appearance, reusing the `Theme.codeBackgroundColor` dynamic-color pattern.
struct ColorPair: Codable, Equatable {
    let light: String
    let dark: String

    var nsLight: NSColor { NSColor(hex: light) ?? .labelColor }
    var nsDark: NSColor { NSColor(hex: dark) ?? .labelColor }

    func resolved(for appearance: NSAppearance) -> NSColor {
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? nsDark : nsLight
    }

    var dynamic: NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? self.nsDark : self.nsLight
        }
    }
}

/// Pure theming engine: scheme → slot mapping and the preset palette library.
enum ColorTheming {
    /// Which palette slot colors a heading of `level` under `scheme`.
    /// nil means "no palette color" — use `labelColor` (the Default scheme).
    /// Standard: H1→0, H2→1, H3–H6→2. Unified: always 0.
    static func slotIndex(forHeadingLevel level: Int, scheme: Coloring) -> Int? {
        switch scheme {
        case .off: return nil
        case .unified: return 0
        case .standard:
            switch level {
            case ...1: return 0
            case 2: return 1
            default: return 2
            }
        }
    }
}
