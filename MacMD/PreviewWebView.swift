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
    /// Two-way scroll-sync channel shared with the editor; nil in contexts with
    /// nothing to sync (tests, preview-only layout).
    var syncBridge: ScrollSyncBridge?
    var documentDirectory: URL?

    static let ruleListID = "macmd-preview-block-network"
    /// The JS-to-Swift message channel carrying the preview's top visible line.
    static let scrollMessageName = "macmdScroll"

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

    /// Push this view's inputs onto the coordinator (its desired state). Split out
    /// so the input-to-handler wiring can be unit tested without a live web view.
    func applyState(to coordinator: Coordinator) {
        coordinator.handler.documentDirectory = documentDirectory
        coordinator.text = text
        coordinator.theme = theme
        coordinator.attachBridge(syncBridge)
    }

    // MARK: - NSViewRepresentable

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let coordinator = context.coordinator
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(coordinator.handler, forURLScheme: MarkdownSchemeHandler.scheme)
        config.websiteDataStore = .nonPersistent()

        // Weakly proxied: the user content controller retains its handlers, so a
        // direct add(coordinator) would cycle coordinator <-> webView.
        config.userContentController.add(WeakScriptMessageHandler(coordinator),
                                         name: Self.scrollMessageName)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = coordinator
        webView.uiDelegate = coordinator
        coordinator.webView = webView
        applyState(to: coordinator)

        // Defense in depth: kill all network at the WebKit layer even if the CSP
        // is somehow bypassed. The rule list is compiled once and cached by the
        // store; reuse the compiled copy across web views, compiling only on a
        // miss. The CSP + custom scheme already block network during the brief
        // async window.
        let store: WKContentRuleListStore = WKContentRuleListStore.default()
        store.lookUpContentRuleList(forIdentifier: Self.ruleListID) { existing, _ in
            if let existing {
                webView.configuration.userContentController.add(existing)
            } else {
                store.compileContentRuleList(forIdentifier: Self.ruleListID,
                                             encodedContentRuleList: Self.contentRuleListJSON()) { compiled, _ in
                    if let compiled { webView.configuration.userContentController.add(compiled) }
                }
            }
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

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        let handler = MarkdownSchemeHandler()
        weak var webView: WKWebView?
        var hasLoadedShell = false

        // Desired state, written by updateNSView / makeNSView.
        var text = ""
        var theme: ThemeController?
        private(set) var syncBridge: ScrollSyncBridge?

        // Last-pushed state, so each render only sends what changed.
        private var lastText: String?
        private var lastCSS: String?
        private var lastAppearanceClass: String?
        private var lastThemeFingerprint: Int?

        /// Wire the shared bridge: the editor drives this preview through the
        /// installed closure, bypassing SwiftUI entirely (see ScrollSyncBridge).
        func attachBridge(_ bridge: ScrollSyncBridge?) {
            guard bridge !== syncBridge else { return }
            syncBridge = bridge
            bridge?.scrollPreviewToLine = { [weak self] line in
                guard let self, self.hasLoadedShell else { return }
                self.webView?.evaluateJavaScript(PreviewWebView.scrollInvocation(line: line))
            }
        }

        /// The preview's own scroll position (its top visible source line),
        /// posted from the shell's scroll listener.
        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard message.name == PreviewWebView.scrollMessageName,
                  let line = message.body as? NSNumber else { return }
            syncBridge?.previewScrolled(toTopLine: line.intValue)
        }

        /// Reconcile the desired state into the live DOM (theme CSS, appearance
        /// class, rendered content, scroll position), pushing only what changed.
        func sync() {
            guard hasLoadedShell, let webView, let theme else { return }

            // Theme CSS + appearance are expensive to build (palette resolve, a
            // customs decode, ~24 per-appearance color resolutions), so recompute
            // them only when a cheap theme fingerprint changes, not on every
            // scroll/text sync.
            let fingerprint = themeFingerprint(theme)
            if fingerprint != lastThemeFingerprint {
                lastThemeFingerprint = fingerprint
                let css = PreviewCSS.css(theme: theme)
                if css != lastCSS {
                    lastCSS = css
                    webView.evaluateJavaScript("window.setThemeCSS(\(MarkdownRenderEngine.jsStringLiteral(css)))")
                }
                let resolved = theme.resolvedTheme
                let cls = EditorBackground.effectiveAppearance(
                    background: resolved.background, isStatic: resolved.isStatic, appearance: theme.appearance
                ).resolvesDark ? "darkAqua" : "aqua"
                if cls != lastAppearanceClass {
                    lastAppearanceClass = cls
                    webView.evaluateJavaScript("window.setAppearance(\(MarkdownRenderEngine.jsStringLiteral(cls)))")
                }
            }

            if text != lastText {
                lastText = text
                if PreviewWebView.allowsLiveRender(byteCount: text.utf8.count) {
                    webView.evaluateJavaScript(MarkdownRenderEngine.renderInvocation(markdown: text))
                }
            }
        }

        /// A cheap fingerprint of every input to PreviewCSS: the theme scalars,
        /// the resolved light/dark state (so an OS appearance flip is caught even
        /// under System mode, and a static theme's luminance side), and the raw
        /// customThemes bytes (so editing the applied custom's colors or
        /// background re-renders).
        private func themeFingerprint(_ t: ThemeController) -> Int {
            var h = Hasher()
            h.combine(t.themeId)
            h.combine(t.fontSize)
            h.combine(t.fontFamilyId)
            h.combine(t.appearance)
            let resolved = t.resolvedTheme
            h.combine(EditorBackground.effectiveAppearance(background: resolved.background,
                                                           isStatic: resolved.isStatic,
                                                           appearance: t.appearance).resolvesDark)
            h.combine(UserDefaults.standard.data(forKey: ThemeSettings.customThemesKey))
            return h.finalize()
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

/// Breaks the retain cycle WKUserContentController.add would otherwise create
/// (the controller retains its handlers; the coordinator owns the web view).
final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var delegate: WKScriptMessageHandler?

    init(_ delegate: WKScriptMessageHandler) {
        self.delegate = delegate
    }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}
