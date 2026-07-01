import Foundation

/// Cross-window chrome preference for the preview pane's visibility. Uses
/// UserDefaults plus a NotificationCenter broadcast (the FormattingPref /
/// WordCountPref pattern) because `@AppStorage` does not reliably propagate
/// across DocumentGroup windows. Exposed as a computed get/set property so
/// callers (the View menu, the toolbar toggle) can flip it with `.toggle()`.
/// Preview is opt-in: unset defaults to false, so documents open editor-only.
enum PreviewPref {
    static let key = "showPreview"
    static let didChange = Notification.Name("MacMD.previewVisibilityChanged")

    static var isVisible: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set {
            UserDefaults.standard.set(newValue, forKey: key)
            NotificationCenter.default.post(name: didChange, object: nil)
        }
    }
}
