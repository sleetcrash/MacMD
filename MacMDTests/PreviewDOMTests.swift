import XCTest
import WebKit
@testable import MacMD

/// Loads the bundled preview shell in a real WKWebView (over the custom scheme,
/// with the CSP + nonce enforced) and evaluates JS against the live DOM, so the
/// render JS (source-line stamping, image routing, theme + appearance hooks) is
/// pinned at the unit level rather than only in the live app smoke test.
@MainActor
final class PreviewHarness: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    let handler: MarkdownSchemeHandler
    let webView: WKWebView
    /// Bodies the shell posted on the recorded message channels, in order.
    private(set) var messages: [(name: String, body: Any)] = []
    private var loaded: CheckedContinuation<Void, Never>?

    init(recording messageNames: [String] = []) {
        let h = MarkdownSchemeHandler()
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.setURLSchemeHandler(h, forURLScheme: MarkdownSchemeHandler.scheme)
        handler = h
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 480, height: 640), configuration: config)
        super.init()
        webView.navigationDelegate = self
        for name in messageNames { webView.configuration.userContentController.add(self, name: name) }
    }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        messages.append((message.name, message.body))
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

    /// Render and wait for `window.__renderComplete` to advance, so async mermaid
    /// rendering has settled before assertions run.
    func renderAndWait(_ markdown: String) async {
        let before = (await eval("window.__renderComplete || 0") as? NSNumber)?.intValue ?? 0
        await eval(MarkdownRenderEngine.renderInvocation(markdown: markdown))
        for _ in 0..<120 {
            let now = (await eval("window.__renderComplete || 0") as? NSNumber)?.intValue ?? 0
            if now > before { return }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
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

    func testSingleNewlineRendersAsLineBreak() async {
        let h = PreviewHarness()
        await h.load()
        await h.render("line one\nline two")
        let brCount = (await h.eval("document.querySelectorAll('p br').length") as? NSNumber)?.intValue
        XCTAssertEqual(brCount, 1, "a single newline inside a paragraph renders as a visible line break")
    }

    func testBulletTasksRenderAsCheckboxesInPlaceOfTheBullet() async {
        let h = PreviewHarness()
        await h.load()
        await h.render("- [ ] open\n- [x] done\n- plain\n\n1. [ ] ordered")
        let boxes = await h.eval("JSON.stringify(Array.from(document.querySelectorAll('input.task-checkbox'))"
            + ".map(function (b) { return [b.getAttribute('data-task-line'), b.checked]; }))") as? String
        XCTAssertEqual(boxes, #"[["1",false],["2",true]]"#, "each bullet task gets a box carrying its source line")
        let bullet = await h.eval("getComputedStyle(document.querySelector('li.task-list-item')).listStyleType") as? String
        XCTAssertEqual(bullet, "none", "the checkbox takes the bullet's place")
        let text = await h.eval("document.querySelector('li.task-list-item').textContent") as? String
        XCTAssertEqual(text, "open", "the [ ] marker is consumed, not shown as text")
        let ordered = (await h.eval("document.querySelectorAll('ol input').length") as? NSNumber)?.intValue
        XCTAssertEqual(ordered, 0, "ordered items stay text: the editor only toggles bullet tasks")
    }

    func testNoBoxWhereTheEditorCouldNotToggleIt() async {
        let h = PreviewHarness()
        await h.load()
        await h.render("> - [ ] quoted\n\n- \\[ ] escaped\n\n- &#91;x] entity\n\n-\n  [ ] late")
        let boxes = (await h.eval("document.querySelectorAll('input.task-checkbox').length") as? NSNumber)?.intValue
        XCTAssertEqual(boxes, 0, "blockquoted, escaped, and next-line boxes stay text, matching the editor")
    }

    func testTaskLinesCountFrontMatterAndNesting() async {
        let h = PreviewHarness()
        await h.load()
        await h.render("---\ntitle: x\n---\n- parent\n\t- [ ] child")
        let line = await h.eval("document.querySelector('input.task-checkbox').getAttribute('data-task-line')") as? String
        XCTAssertEqual(line, "5", "a nested task under front matter maps to its full-document line")
    }

    func testCheckboxClickPostsItsSourceLine() async {
        let h = PreviewHarness(recording: [PreviewWebView.taskToggleMessageName])
        await h.load()
        await h.render("intro\n\n- [ ] first\n- [ ] second")
        await h.eval("document.querySelectorAll('input.task-checkbox')[1].click()")
        for _ in 0..<40 where h.messages.isEmpty { try? await Task.sleep(nanoseconds: 25_000_000) }
        XCTAssertEqual(h.messages.map(\.name), [PreviewWebView.taskToggleMessageName])
        XCTAssertEqual((h.messages.first?.body as? NSNumber)?.intValue, 4)
    }

    func testExportedCheckboxesAreStatic() async throws {
        let h = PreviewHarness()
        await h.load()
        let html = try await h.webView.callAsyncJavaScript("return await window.renderForExport(md)",
                                                           arguments: ["md": "- [x] done"],
                                                           contentWorld: .page) as? String
        XCTAssertEqual(html?.contains("disabled"), true, "an exported box cannot be toggled")
        XCTAssertEqual(html?.contains("data-task-line"), false, "no editor wiring leaks into the export")
        XCTAssertEqual(html?.contains("checked"), true)
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

    func testFrontMatterRendersAsMetadataBlockNotHeading() async {
        let h = PreviewHarness()
        await h.load()
        await h.render("---\nname: macmd\ndescription: a markdown editor\n---\n# Real Heading\nBody\n")
        let fmCount = (await h.eval("document.querySelectorAll('.front-matter').length") as? NSNumber)?.intValue
        XCTAssertEqual(fmCount, 1, "front matter renders as its own block")
        let keys = await h.eval(
            "Array.from(document.querySelectorAll('.front-matter .fm-key')).map(function (e) { return e.textContent; }).join(',')"
        ) as? String
        XCTAssertEqual(keys, "name,description")
        // Without the split, markdown-it read "description: ..." + "---" as a
        // setext H2 (the bold/pink metadata bug).
        let h2Count = (await h.eval("document.querySelectorAll('h2').length") as? NSNumber)?.intValue
        XCTAssertEqual(h2Count, 0, "metadata must not parse as a setext heading")
        // Scroll-sync line numbers still count the stripped block: the heading
        // sits on source line 5.
        let line = await h.eval("document.querySelector('h1').getAttribute('data-source-line')") as? String
        XCTAssertEqual(line, "5")
    }

    func testFrontMatterContentIsHTMLEscaped() async {
        let h = PreviewHarness()
        await h.load()
        await h.render("---\nname: <img src=x onerror=alert(1)>\n---\nBody\n")
        let imgs = (await h.eval("document.querySelectorAll('.front-matter img').length") as? NSNumber)?.intValue
        XCTAssertEqual(imgs, 0, "front-matter values are inert text, never markup")
    }

    func testLeadingDashesWithoutClosingDelimiterStayMarkdown() async {
        let h = PreviewHarness()
        await h.load()
        await h.render("---\nJust a line\n")
        let fmCount = (await h.eval("document.querySelectorAll('.front-matter').length") as? NSNumber)?.intValue
        XCTAssertEqual(fmCount, 0, "an unclosed delimiter is not front matter")
        let hrCount = (await h.eval("document.querySelectorAll('hr').length") as? NSNumber)?.intValue
        XCTAssertEqual(hrCount, 1, "the bare --- still renders as a thematic break")
    }
}
