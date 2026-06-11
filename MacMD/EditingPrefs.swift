import Foundation

/// The global spelling defaults, set from the Settings window's Editing tab and
/// the Edit > Spelling and Grammar menu. Read via a direct UserDefaults read
/// and broadcast on change (NOT @AppStorage alone, which does not reliably
/// propagate across DocumentGroup windows in MacMD), mirroring `FormattingPref`.
/// Spell check defaults to on (the pre-1.5.0 hardcoded behavior); grammar
/// defaults to off, matching the system default.
enum SpellingPref {
    static let spellingKey = "checkSpellingWhileTyping"
    static let grammarKey = "checkGrammarWithSpelling"
    static let didChange = Notification.Name("MacMDSpellingPrefDidChange")

    static var checkSpelling: Bool {
        UserDefaults.standard.object(forKey: spellingKey) == nil
            ? true
            : UserDefaults.standard.bool(forKey: spellingKey)
    }

    static var checkGrammar: Bool {
        UserDefaults.standard.bool(forKey: grammarKey)
    }

    static func setCheckSpelling(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: spellingKey)
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    static func setCheckGrammar(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: grammarKey)
        NotificationCenter.default.post(name: didChange, object: nil)
    }
}

/// The preferred size, in points, for NEW document windows, set from the
/// Settings window's Editing tab. Existing windows are never touched; the value
/// feeds each new window's ideal frame. Bounds keep a window usable: the
/// minimums match the editor's layout minimums, the maximums cap runaway input.
enum NewWindowSize {
    static let widthKey = "newWindowWidth"
    static let heightKey = "newWindowHeight"

    static let defaultWidth: Double = 760
    static let defaultHeight: Double = 680
    static let minWidth: Double = 520
    static let minHeight: Double = 400
    static let maxWidth: Double = 5000
    static let maxHeight: Double = 5000

    static var width: Double {
        clampWidth(UserDefaults.standard.object(forKey: widthKey) as? Double ?? defaultWidth)
    }

    static var height: Double {
        clampHeight(UserDefaults.standard.object(forKey: heightKey) as? Double ?? defaultHeight)
    }

    static func set(width: Double, height: Double) {
        UserDefaults.standard.set(clampWidth(width), forKey: widthKey)
        UserDefaults.standard.set(clampHeight(height), forKey: heightKey)
    }

    static func clampWidth(_ w: Double) -> Double {
        min(maxWidth, max(minWidth, w.rounded()))
    }

    static func clampHeight(_ h: Double) -> Double {
        min(maxHeight, max(minHeight, h.rounded()))
    }
}
