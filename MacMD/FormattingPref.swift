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
