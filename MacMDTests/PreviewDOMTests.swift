import XCTest
import WebKit
@testable import MacMD

/// Loads the bundled preview shell in a real WKWebView (over the custom scheme,
/// with the CSP + nonce enforced) and evaluates JS against the live DOM, so the
/// render JS (source-line stamping, image routing, theme + appearance hooks) is
/// pinned at the unit level rather than only in the live app smoke test.
@MainActor
final class PreviewHarness: NSObject, WKNavigationDelegate {
    let handler: MarkdownSchemeHandler
    let webView: WKWebView
    private var loaded: CheckedContinuation<Void, Never>?

    override init() {
        let h = MarkdownSchemeHandler()
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.setURLSchemeHandler(h, forURLScheme: MarkdownSchemeHandler.scheme)
        handler = h
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 480, height: 640), configuration: config)
        super.init()
        webView.navigationDelegate = self
    }

    func load() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            loaded = cont
            webView.load(URLRequest(url: URL(string: "\(MarkdownSchemeHandler.scheme)://app/index.html")!))
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finishLoad() }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finishLoad() }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finishLoad() }
    private func finishLoad() { loaded?.resume(); loaded = nil }

    @discardableResult
    func eval(_ js: String) async -> Any? {
        await withCheckedContinuation { (cont: CheckedContinuation<Any?, Never>) in
            webView.evaluateJavaScript(js) { result, _ in cont.resume(returning: result) }
        }
    }

    func render(_ markdown: String) async {
        await eval(MarkdownRenderEngine.renderInvocation(markdown: markdown))
    }
}

@MainActor
final class PreviewDOMTests: XCTestCase {

    func testImageSrcRewrittenToResourceScheme() async {
        let h = PreviewHarness()
        await h.load()
        await h.render("![pic](pic.png)")
        let src = await h.eval("document.querySelector('img').getAttribute('src')") as? String
        XCTAssertEqual(src?.hasPrefix("macmd-resource://img/"), true, "relative image src routed through the img scheme")

        // The rewritten escaping token, decoded through the handler, escapes the
        // document directory and resolves to nothing (404).
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        h.handler.documentDirectory = dir
        XCTAssertNil(h.handler.imageURL(forToken: "..%2Fescape.png"))
    }

    func testSourceLinesAndScrollToLine() async {
        let h = PreviewHarness()
        await h.load()
        await h.render("# a\n\npara")
        let count = (await h.eval("document.querySelectorAll('[data-source-line]').length") as? NSNumber)?.intValue ?? 0
        XCTAssertGreaterThan(count, 0, "block elements carry data-source-line")
        let type = await h.eval("typeof window.scrollToLine") as? String
        XCTAssertEqual(type, "function")
    }

    func testActiveAppearanceBlockApplies() async {
        let h = PreviewHarness()
        await h.load()
        await h.eval("window.setThemeCSS('html.darkAqua body { color: rgb(10, 20, 30); }')")
        await h.eval("window.setAppearance('darkAqua')")
        let cls = await h.eval("document.documentElement.className") as? String
        XCTAssertEqual(cls, "darkAqua")
        // The dark block now applies with no prefers-color-scheme dependency.
        let color = await h.eval("getComputedStyle(document.body).color") as? String
        XCTAssertEqual(color, "rgb(10, 20, 30)")
    }
}
