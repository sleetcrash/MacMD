import XCTest
@testable import MacMD

final class MermaidEngineTests: XCTestCase {

    func testContainsMermaidDetectsMermaidFences() {
        XCTAssertTrue(MarkdownRenderEngine.containsMermaid(in: "```mermaid\nflowchart TD\n```\n"))
        XCTAssertTrue(MarkdownRenderEngine.containsMermaid(in: "```Mermaid\nx\n```\n"))
        XCTAssertTrue(MarkdownRenderEngine.containsMermaid(in: "``` mermaid\nx\n```\n"))
        XCTAssertTrue(MarkdownRenderEngine.containsMermaid(in: "```mermaid gantt\nx\n```\n"))

        XCTAssertFalse(MarkdownRenderEngine.containsMermaid(in: "```swift\nx\n```\n"))
        XCTAssertFalse(MarkdownRenderEngine.containsMermaid(in: "```mermaidish\nx\n```\n"))
        XCTAssertFalse(MarkdownRenderEngine.containsMermaid(in: "the word mermaid in prose\n"))
        XCTAssertFalse(MarkdownRenderEngine.containsMermaid(in: ""))
    }

    // Security invariant guard: the CSP never permits eval. This goes RED only if
    // a future change weakens script-src; that change is the bug, not the test.
    func testCSPNeverAllowsUnsafeEval() {
        let csp = MarkdownRenderEngine.cspHeaderValue(nonce: MarkdownRenderEngine.makeNonce())
        XCTAssertFalse(csp.contains("unsafe-eval"))
        let scriptSrc = csp.split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.hasPrefix("script-src") }
        XCTAssertEqual(scriptSrc?.contains("unsafe-inline"), false)
        XCTAssertEqual(scriptSrc?.contains("unsafe-eval"), false)
    }
}
