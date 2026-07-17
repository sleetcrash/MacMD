import Foundation

/// The document window's pane layout: editor only, split, or preview only.
enum PaneMode: String, CaseIterable {
    case editor, split, preview

    var displayName: String {
        switch self {
        case .editor: return "Editor Only"
        case .split: return "Split"
        case .preview: return "Preview Only"
        }
    }

    /// The corner layout toggle's glyph for this layout.
    var systemImage: String {
        switch self {
        case .editor: return "rectangle.lefthalf.inset.filled"
        case .split: return "rectangle.split.2x1"
        case .preview: return "rectangle.righthalf.inset.filled"
        }
    }
}

/// Cross-window chrome preference for the pane layout. Uses UserDefaults plus a
/// NotificationCenter broadcast (the FormattingPref / WordCountPref pattern)
/// because `@AppStorage` does not reliably propagate across DocumentGroup
/// windows. Replaces the 2.0 boolean show-preview pref; `migrate()` fast-cuts
/// an existing showPreview=true to `.split` at launch.
enum PaneModePref {
    static let key = "paneMode"
    /// The pre-2.1 boolean key, consumed once by `migrate()`.
    static let legacyKey = "showPreview"
    static let didChange = Notification.Name("MacMD.paneModeChanged")

    static var mode: PaneMode {
        PaneMode(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .editor
    }

    static func set(_ mode: PaneMode) {
        UserDefaults.standard.set(mode.rawValue, forKey: key)
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    /// Whether the preview pane is showing (split or preview-only); drives the
    /// View menu's Show Preview checkmark.
    static var previewVisible: Bool { mode != .editor }

    /// One-shot legacy migration, called at launch: read the old boolean,
    /// write the equivalent mode, delete the old key.
    static func migrate() {
        let d = UserDefaults.standard
        guard d.string(forKey: key) == nil, d.object(forKey: legacyKey) != nil else { return }
        d.set((d.bool(forKey: legacyKey) ? PaneMode.split : .editor).rawValue, forKey: key)
        d.removeObject(forKey: legacyKey)
    }
}
