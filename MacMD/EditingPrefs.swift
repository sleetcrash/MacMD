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
