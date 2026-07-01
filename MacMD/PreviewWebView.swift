import WebKit

/// Navigation policy for the preview web view (the security gate for links). The
/// only load permitted is the initial programmatic `macmd-resource` main-frame
/// load; a clicked http(s) link opens in the default browser; everything else,
/// including `javascript:`, `data:`, `file:`, and any other non-http scheme, is
/// cancelled so it never reaches `NSWorkspace.open` or executes.
enum PreviewNavigation {
    enum Action: Equatable {
        case allow
        case cancel
        case openExternally(URL)
    }

    static func decision(isInitialLoad: Bool, navigationType: WKNavigationType, url: URL?) -> Action {
        guard let url else { return .cancel }
        if isInitialLoad, navigationType == .other, url.scheme == MarkdownSchemeHandler.scheme {
            return .allow
        }
        if navigationType == .linkActivated,
           let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
            return .openExternally(url)
        }
        return .cancel
    }
}
