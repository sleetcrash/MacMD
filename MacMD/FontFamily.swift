import AppKit

/// A curated editor body font. `font(size:)`/`boldFont(size:)` always return a
/// usable NSFont, falling back to the monospaced system font if a named face
/// fails to load, so an unknown id or a missing font never crashes or shows a
/// substitute "ransom note" face. Data-only (a `Resolver` enum, no stored
/// closures) so the type is `Sendable` and the `all` list is a safe global.
struct FontFamily: Identifiable, Equatable, Sendable {
    enum Resolver: Equatable, Sendable {
        case systemMono          // .monospacedSystemFont (the current default)
        case system              // .systemFont (SF sans)
        case serif               // system font with the .serif design (New York)
        case named(String)       // a named installed face, e.g. "Menlo"
    }

    let id: String
    let displayName: String
    let isMonospace: Bool
    let resolver: Resolver

    func font(size: CGFloat) -> NSFont { Self.make(resolver, size: size, bold: false) }
    func boldFont(size: CGFloat) -> NSFont { Self.make(resolver, size: size, bold: true) }

    private static func make(_ resolver: Resolver, size: CGFloat, bold: Bool) -> NSFont {
        switch resolver {
        case .systemMono:
            return .monospacedSystemFont(ofSize: size, weight: bold ? .bold : .regular)
        case .system:
            return .systemFont(ofSize: size, weight: bold ? .bold : .regular)
        case .serif:
            let base = NSFont.systemFont(ofSize: size, weight: bold ? .bold : .regular)
            var descriptor = base.fontDescriptor
            if let serif = descriptor.withDesign(.serif) { descriptor = serif }
            if bold { descriptor = descriptor.withSymbolicTraits(.bold) }
            return NSFont(descriptor: descriptor, size: size) ?? base
        case .named(let name):
            let fallback = NSFont.monospacedSystemFont(ofSize: size, weight: bold ? .bold : .regular)
            guard let base = NSFont(name: name, size: size) else { return fallback }
            guard bold else { return base }
            let bolded = NSFontManager.shared.convert(base, toHaveTrait: .boldFontMask)
            return bolded.fontDescriptor.symbolicTraits.contains(.bold)
                ? bolded
                : .systemFont(ofSize: size, weight: .bold)
        }
    }

    /// The curated set. System Monospace is first and is the default.
    static let all: [FontFamily] = [
        FontFamily(id: "system-mono", displayName: "System Monospace", isMonospace: true, resolver: .systemMono),
        FontFamily(id: "menlo", displayName: "Menlo", isMonospace: true, resolver: .named("Menlo")),
        FontFamily(id: "monaco", displayName: "Monaco", isMonospace: true, resolver: .named("Monaco")),
        FontFamily(id: "courier-new", displayName: "Courier New", isMonospace: true, resolver: .named("Courier New")),
        FontFamily(id: "system", displayName: "System", isMonospace: false, resolver: .system),
        FontFamily(id: "new-york", displayName: "New York", isMonospace: false, resolver: .serif),
        FontFamily(id: "helvetica-neue", displayName: "Helvetica Neue", isMonospace: false, resolver: .named("Helvetica Neue")),
        FontFamily(id: "georgia", displayName: "Georgia", isMonospace: false, resolver: .named("Georgia")),
    ]

    static let `default` = all[0]

    /// The family for a stored id, or the default for an unknown/garbage id.
    static func resolve(id: String) -> FontFamily {
        all.first { $0.id == id } ?? .default
    }
}
