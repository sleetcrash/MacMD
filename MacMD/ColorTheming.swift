import AppKit

extension NSColor {
    /// Builds an sRGB color from a `#RRGGBB` (or `RRGGBB`) string. Returns nil
    /// for malformed input so callers can fall back to a semantic color.
    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, s.allSatisfy(\.isHexDigit), let v = Int(s, radix: 16) else { return nil }
        let r = CGFloat((v >> 16) & 0xFF) / 255
        let g = CGFloat((v >> 8) & 0xFF) / 255
        let b = CGFloat(v & 0xFF) / 255
        self.init(srgbRed: r, green: g, blue: b, alpha: 1)
    }

    /// Uppercase `#RRGGBB` of the color resolved into sRGB.
    var hexString: String {
        guard let c = usingColorSpace(.sRGB) else { return "#000000" }
        let r = Int((c.redComponent * 255).rounded())
        let g = Int((c.greenComponent * 255).rounded())
        let b = Int((c.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

/// How many distinct heading colors are in play.
enum Coloring: String, Codable {
    /// `.off` colors nothing (headings use the system label color); shown as "Default" in the UI.
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

    /// Whether this Mode resolves dark right now (System follows the OS).
    @MainActor var resolvesDark: Bool {
        switch self {
        case .light: return false
        case .dark: return true
        case .system:
            return NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
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

    var dynamic: NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? self.nsDark : self.nsLight
        }
    }
}

/// A named, ordered set of up to 3 light/dark slots plus the scheme it belongs
/// to. Standard palettes have 3 slots (H1/H2/H3); Unified palettes have 1.
struct Palette: Codable, Equatable, Identifiable {
    let id: String
    var name: String
    let scheme: Coloring
    let slots: [ColorPair]
    var background: ColorPair = EditorBackground.defaultPair
    var isStatic: Bool = false

    /// The dynamic color for a heading of `level` under this palette, or
    /// `labelColor` if the level maps outside the slots.
    func headingColor(level: Int) -> NSColor {
        guard let idx = ColorTheming.slotIndex(forHeadingLevel: level, scheme: scheme),
              idx < slots.count else { return .labelColor }
        return slots[idx].dynamic
    }
}

extension Palette {
    enum CodingKeys: String, CodingKey {
        case id, name, scheme, slots, background, isStatic
    }

    /// Legacy saved palettes predate `background`/`isStatic`; both fall back to
    /// their defaults so old prefs blobs decode unchanged. A static palette
    /// collapses every pair (background and slots) to its light value, so a
    /// stale dark-mode variant can never resurface after a later re-encode.
    /// Declared in this extension, not the struct body, so the compiler keeps
    /// synthesizing the memberwise `init(id:name:scheme:slots:)` every existing
    /// call site relies on.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        scheme = try c.decode(Coloring.self, forKey: .scheme)
        let decodedSlots = try c.decode([ColorPair].self, forKey: .slots)
        let decodedBackground = try c.decodeIfPresent(ColorPair.self, forKey: .background) ?? EditorBackground.defaultPair
        isStatic = try c.decodeIfPresent(Bool.self, forKey: .isStatic) ?? false
        if isStatic {
            background = ColorPair(light: decodedBackground.light, dark: decodedBackground.light)
            slots = decodedSlots.map { ColorPair(light: $0.light, dark: $0.light) }
        } else {
            background = decodedBackground
            slots = decodedSlots
        }
    }

    /// One flat, backgroundless tint per curated background preset, for the
    /// Theme dropdown's tint row.
    static let tintThemes: [Palette] = BackgroundPreset.all.map { preset in
        Palette(id: preset.id.replacingOccurrences(of: "bg.", with: "tint."),
                name: preset.name, scheme: .off, slots: [], background: preset.pair)
    }

    /// The app's out-of-the-box theme: no heading color, the standard editor
    /// background.
    static let defaultTheme = Palette(id: "default", name: "Default", scheme: .off, slots: [])
}

/// Pure theming engine: scheme → slot mapping and the preset palette library.
enum ColorTheming {
    /// Which palette slot colors a heading of `level` under `scheme`.
    /// nil means "no palette color", use `labelColor` (the Default scheme).
    /// Standard: H1→0, H2→1, H3-H6→2. Unified: always 0.
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

    static let standardPresets: [Palette] = [
        Palette(id: "std.rgb", name: "RGB", scheme: .standard, slots: [
            ColorPair(light: "#C13F50", dark: "#E86577"),
            ColorPair(light: "#2E8049", dark: "#5CBE7C"),
            ColorPair(light: "#2E86AB", dark: "#54A9CC"),
        ]),
        Palette(id: "std.cmyk", name: "CMY(K)", scheme: .standard, slots: [
            ColorPair(light: "#1F5C82", dark: "#5B9AC4"),
            ColorPair(light: "#A62A43", dark: "#D85A72"),
            ColorPair(light: "#B5851C", dark: "#E0B445"),
        ]),
        Palette(id: "std.eva00", name: "EVA-00", scheme: .standard, slots: [
            ColorPair(light: "#052A6A", dark: "#5566CC"),
            ColorPair(light: "#03559E", dark: "#4E84C8"),
            ColorPair(light: "#7C84C0", dark: "#CDD3F4"),
        ]),
        Palette(id: "std.eva01", name: "EVA-01", scheme: .standard, slots: [
            ColorPair(light: "#7A45B0", dark: "#A86FE0"),
            ColorPair(light: "#5E9E2C", dark: "#8EDF5F"),
            ColorPair(light: "#D45F2A", dark: "#F0915F"),
        ]),
        Palette(id: "std.eva02", name: "EVA-02", scheme: .standard, slots: [
            ColorPair(light: "#861712", dark: "#C9483F"),
            ColorPair(light: "#C0392B", dark: "#E2604E"),
            ColorPair(light: "#C95F28", dark: "#E3733B"),
        ]),
        Palette(id: "std.evaend", name: "EVA-END", scheme: .standard, slots: [
            ColorPair(light: "#E63F3B", dark: "#FD5B57"),
            ColorPair(light: "#364699", dark: "#6A7AD0"),
            ColorPair(light: "#6F64A0", dark: "#A99FD8"),
        ]),
    ]

    static let unifiedPresets: [Palette] = [
        Palette(id: "uni.red", name: "Red", scheme: .unified, slots: [ColorPair(light: "#A62A43", dark: "#D85A72")]),
        Palette(id: "uni.orange", name: "Orange", scheme: .unified, slots: [ColorPair(light: "#D45F2A", dark: "#F0915F")]),
        Palette(id: "uni.yellow", name: "Yellow", scheme: .unified, slots: [ColorPair(light: "#B5851C", dark: "#E0B445")]),
        Palette(id: "uni.green", name: "Green", scheme: .unified, slots: [ColorPair(light: "#1F7A5C", dark: "#43B488")]),
        Palette(id: "uni.teal", name: "Teal", scheme: .unified, slots: [ColorPair(light: "#2E86AB", dark: "#54A9CC")]),
        Palette(id: "uni.blue", name: "Blue", scheme: .unified, slots: [ColorPair(light: "#364699", dark: "#6A7AD0")]),
        Palette(id: "uni.purple", name: "Purple", scheme: .unified, slots: [ColorPair(light: "#7A45B0", dark: "#A86FE0")]),
        Palette(id: "uni.periwinkle", name: "Periwinkle", scheme: .unified, slots: [ColorPair(light: "#7C84C0", dark: "#CDD3F4")]),
    ]

    static let defaultStandardId = "std.rgb"
    static let defaultUnifiedId = "uni.red"

    static func presets(for scheme: Coloring) -> [Palette] {
        switch scheme {
        case .off: return []
        case .unified: return unifiedPresets
        case .standard: return standardPresets
        }
    }

    static func preset(id: String) -> Palette? {
        (standardPresets + unifiedPresets).first { $0.id == id }
    }
}
