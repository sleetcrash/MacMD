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

/// The sandboxed markdown preview. (Grows into the full `NSViewRepresentable` in
/// M2.6; for now it owns the pure security/render seams so they can be unit
/// tested without assembling a live web view.)
struct PreviewWebView {

    /// A WKContentRuleList (as JSON) that blocks every URL, then ignores previous
    /// rules for the custom scheme: the preview can still load the bundled shell
    /// and assets but nothing on the network, even if the CSP were bypassed. The
    /// block rule must precede the ignore rule.
    static func contentRuleListJSON() -> String {
        """
        [
          { "trigger": { "url-filter": ".*" }, "action": { "type": "block" } },
          { "trigger": { "url-filter": "^\(MarkdownSchemeHandler.scheme):" }, "action": { "type": "ignore-previous-rules" } }
        ]
        """
    }
}
