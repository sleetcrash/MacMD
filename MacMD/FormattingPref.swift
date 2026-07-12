import Foundation

/// The global "show formatting" (Styled vs Plain) preference. Read via a direct
/// UserDefaults read and broadcast on change (NOT @AppStorage alone, which does
/// not reliably propagate across DocumentGroup windows in MacMD), mirroring
/// `WordCountPref`. Defaults to true (styled) when never set, so the out-of-box
/// experience is unchanged.
enum FormattingPref {
    static let key = "showFormatting"
    static let didChange = Notification.Name("MacMDFormattingPrefDidChange")

    static var isOn: Bool {
        UserDefaults.standard.object(forKey: key) == nil
            ? true
            : UserDefaults.standard.bool(forKey: key)
    }

    static func set(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: key)
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    /// Highlighting runs only when formatting is shown AND the document is under
    /// the soft size limit. Turning formatting back on must NOT re-highlight a
    /// document that was disabled for being over the limit.
    static func shouldHighlight(showFormatting: Bool, overSoftSizeLimit: Bool) -> Bool {
        showFormatting && !overSoftSizeLimit
    }
}

/// The global "show line numbers" preference for the editor gutter. On by
/// default; independent of the Styled/Plain formatting mode (the gutter was
/// Plain-only before 2.1). Same UserDefaults + broadcast pattern as above.
enum LineNumbersPref {
    static let key = "showLineNumbers"
    static let didChange = Notification.Name("MacMDLineNumbersPrefDidChange")

    static var isOn: Bool {
        UserDefaults.standard.object(forKey: key) == nil
            ? true
            : UserDefaults.standard.bool(forKey: key)
    }

    static func set(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: key)
        NotificationCenter.default.post(name: didChange, object: nil)
    }
}
