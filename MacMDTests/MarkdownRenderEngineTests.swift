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
}
