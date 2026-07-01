import XCTest
@testable import MacMD

final class MarkdownRenderEngineTests: XCTestCase {

    // MARK: - Nonce

    func testMakeNonceIsUnique128BitBase64() {
        let a = MarkdownRenderEngine.makeNonce()
        let b = MarkdownRenderEngine.makeNonce()
        XCTAssertNotEqual(a, b, "each render must get a fresh nonce")
        for nonce in [a, b] {
            let decoded = Data(base64Encoded: nonce)
            XCTAssertNotNil(decoded, "nonce must be valid base64")
            XCTAssertEqual(decoded?.count, 16, "nonce must be 128 bits")
        }
    }

    // MARK: - Content-Security-Policy

    func testCSPHeaderIsTheLockedPolicy() {
        let csp = MarkdownRenderEngine.cspHeaderValue(nonce: "NTEST")
        XCTAssertEqual(csp, "default-src 'none'; script-src 'nonce-NTEST'; style-src 'unsafe-inline' macmd-resource:; img-src macmd-resource: data:; font-src macmd-resource:; connect-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'; frame-src 'none'; sandbox allow-scripts")

        // Guard the security-critical invariants directive by directive.
        let directives = csp.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
        let scriptSrc = directives.first { $0.hasPrefix("script-src") }
        let styleSrc = directives.first { $0.hasPrefix("style-src") }
        let imgSrc = directives.first { $0.hasPrefix("img-src") }

        XCTAssertFalse(csp.contains("'unsafe-eval'"), "unsafe-eval is a red line")
        XCTAssertEqual(scriptSrc?.contains("'unsafe-inline'"), false, "script-src must not allow inline scripts")
        // A nonce on style-src would nullify 'unsafe-inline' per CSP3 and block
        // mermaid's runtime-injected styles.
        XCTAssertEqual(styleSrc?.contains("'nonce-"), false, "style-src must carry no nonce")
        XCTAssertEqual(imgSrc?.contains("http"), false, "img-src must not allow remote images")
        XCTAssertEqual(imgSrc?.contains("*"), false, "img-src must not use a wildcard")
    }

    // MARK: - Shell HTML

    func testShellHTMLStampsNonceAndCSSWithoutPlaceholders() {
        let html = MarkdownRenderEngine.shellHTML(nonce: "NTEST", css: "body{color:red}")
        XCTAssertTrue(html.contains("nonce=\"NTEST\""))
        XCTAssertTrue(html.contains("body{color:red}"))
        XCTAssertTrue(html.contains("macmd-resource://app/markdown-it.min.js"))
        XCTAssertTrue(html.contains("macmd-resource://app/mermaid.min.js"))
        XCTAssertTrue(html.contains("macmd-resource://app/preview-base.css"))
        XCTAssertFalse(html.contains("__MACMD_NONCE__"), "every nonce placeholder stamped")
        XCTAssertFalse(html.contains("__MACMD_CSS__"), "the css placeholder stamped")
    }

    // MARK: - Render invocation

    func testRenderInvocationJSONEncodesMarkdownArgument() {
        let input = "# Hi \"q\"\n</script>\nline\twith\ttabs"
        let call = MarkdownRenderEngine.renderInvocation(markdown: input)
        XCTAssertTrue(call.hasPrefix("window.render("))
        XCTAssertTrue(call.hasSuffix(")"))
        let start = call.index(call.startIndex, offsetBy: "window.render(".count)
        let end = call.index(before: call.endIndex)
        let jsonPart = String(call[start..<end])
        let decoded = try? JSONSerialization.jsonObject(with: Data(jsonPart.utf8), options: [.fragmentsAllowed])
        XCTAssertEqual(decoded as? String, input, "the markdown round-trips losslessly through JSON")
    }
}
