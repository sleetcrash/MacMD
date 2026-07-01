import SwiftUI
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

/// The sandboxed markdown preview: a WKWebView that loads the offline shell over
/// the custom scheme, renders the document via markdown-it, mirrors the editor
/// theme, and follows the editor's top visible line for scroll sync. Network is
/// blocked at three layers (custom scheme, CSP header, content rule list).
struct PreviewWebView: NSViewRepresentable {
    let text: String
    @ObservedObject var theme: ThemeController
    var topVisibleLine: Int?
    var documentDirectory: URL?

    // MARK: - Pure seams (unit tested)

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

    /// Whether the preview should live-render a document of this UTF-8 byte size,
    /// or leave it static to protect typing on huge files. Mirrors the
    /// highlighter's soft-size gate (over the limit, live styling is off).
    static func allowsLiveRender(byteCount: Int) -> Bool {
        byteCount < MarkdownDocument.softSizeLimit
    }

    /// The JS call that scrolls the preview to a source line (editor-to-preview
    /// scroll sync).
    static func scrollInvocation(line: Int) -> String {
        "scrollToLine(\(line))"
    }

    /// A JSON-encoded JS string literal, so an arbitrary CSS/appearance payload is
    /// delivered as an inert string argument to a `window.*` function.
    static func jsStringLiteral(_ s: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: s, options: [.fragmentsAllowed]),
              let json = String(data: data, encoding: .utf8) else { return "\"\"" }
        return json
    }

    /// Push this view's inputs onto the coordinator (its desired state). Split out
    /// so the input-to-handler wiring can be unit tested without a live web view.
    func applyState(to coordinator: Coordinator) {
        coordinator.handler.documentDirectory = documentDirectory
        coordinator.text = text
        coordinator.theme = theme
        coordinator.topVisibleLine = topVisibleLine
    }

    // MARK: - NSViewRepresentable

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let coordinator = context.coordinator
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(coordinator.handler, forURLScheme: MarkdownSchemeHandler.scheme)
        config.websiteDataStore = .nonPersistent()

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = coordinator
        webView.uiDelegate = coordinator
        coordinator.webView = webView
        applyState(to: coordinator)

        // Defense in depth: kill all network at the WebKit layer even if the CSP
        // is somehow bypassed. Compiles async; the CSP + custom scheme already
        // block network during the brief compile window.
        WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "macmd-preview-block-network",
            encodedContentRuleList: Self.contentRuleListJSON()
        ) { list, _ in
            if let list { webView.configuration.userContentController.add(list) }
        }

        if let url = URL(string: "\(MarkdownSchemeHandler.scheme)://app/index.html") {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        applyState(to: context.coordinator)
        context.coordinator.sync()
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let handler = MarkdownSchemeHandler()
        weak var webView: WKWebView?
        var hasLoadedShell = false

        // Desired state, written by updateNSView / makeNSView.
        var text = ""
        var theme: ThemeController?
        var topVisibleLine: Int?

        // Last-pushed state, so each render only sends what changed.
        private var lastText: String?
        private var lastTopLine: Int?
        private var lastCSS: String?
        private var lastAppearanceClass: String?

        /// Reconcile the desired state into the live DOM (theme CSS, appearance
        /// class, rendered content, scroll position), pushing only what changed.
        func sync() {
            guard hasLoadedShell, let webView, let theme else { return }

            let css = PreviewCSS.css(theme: theme)
            if css != lastCSS {
                lastCSS = css
                webView.evaluateJavaScript("window.setThemeCSS(\(PreviewWebView.jsStringLiteral(css)))")
            }

            let cls = EditorBackground.effectiveAppearance(
                mode: theme.backgroundMode, hex: theme.customBackgroundHex, appearance: theme.appearance
            ).resolvesDark ? "darkAqua" : "aqua"
            if cls != lastAppearanceClass {
                lastAppearanceClass = cls
                webView.evaluateJavaScript("window.setAppearance(\(PreviewWebView.jsStringLiteral(cls)))")
            }

            if text != lastText {
                lastText = text
                if PreviewWebView.allowsLiveRender(byteCount: text.utf8.count) {
                    webView.evaluateJavaScript(MarkdownRenderEngine.renderInvocation(markdown: text))
                }
            }

            if let line = topVisibleLine, line != lastTopLine {
                lastTopLine = line
                webView.evaluateJavaScript(PreviewWebView.scrollInvocation(line: line))
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !hasLoadedShell else { return }
            hasLoadedShell = true
            sync()
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            let isInitial = !hasLoadedShell && (navigationAction.targetFrame?.isMainFrame ?? false)
            switch PreviewNavigation.decision(isInitialLoad: isInitial,
                                              navigationType: navigationAction.navigationType,
                                              url: navigationAction.request.url) {
            case .allow:
                decisionHandler(.allow)
            case .cancel:
                decisionHandler(.cancel)
            case .openExternally(let url):
                decisionHandler(.cancel)
                NSWorkspace.shared.open(url)
            }
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            nil  // block window.open
        }
    }
}
