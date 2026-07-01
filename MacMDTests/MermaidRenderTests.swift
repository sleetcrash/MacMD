import XCTest
import WebKit
@testable import MacMD

@MainActor
final class MermaidRenderTests: XCTestCase {

    func testMermaidFlowchartRendersInlineSVG() async {
        let h = PreviewHarness()
        await h.load()
        await h.renderAndWait("```mermaid\nflowchart TD; A-->B\n```\n")

        let svgCount = (await h.eval("document.querySelectorAll('svg').length") as? NSNumber)?.intValue ?? 0
        XCTAssertGreaterThanOrEqual(svgCount, 1, "the mermaid fence rendered to inline SVG under strict CSP")

        let leftover = (await h.eval("document.querySelectorAll('code.language-mermaid').length") as? NSNumber)?.intValue ?? -1
        XCTAssertEqual(leftover, 0, "the muted mermaid code block is replaced")

        let startOnLoad = await h.eval("window.__mermaidConfig && window.__mermaidConfig.startOnLoad")
        XCTAssertEqual((startOnLoad as? NSNumber)?.boolValue, false)
        let security = await h.eval("window.__mermaidConfig && window.__mermaidConfig.securityLevel") as? String
        XCTAssertEqual(security, "strict")
    }

    func testUnchangedDiagramReusesCachedSVG() async {
        let h = PreviewHarness()
        await h.load()
        await h.renderAndWait("```mermaid\nflowchart TD; A-->B\n```\n")
        let after1 = (await h.eval("window.__mermaidRenderCount") as? NSNumber)?.intValue ?? -1
        XCTAssertEqual(after1, 1)

        // Same diagram, extra prose: unchanged source reuses the cache.
        await h.renderAndWait("```mermaid\nflowchart TD; A-->B\n```\n\nsome prose\n")
        let after2 = (await h.eval("window.__mermaidRenderCount") as? NSNumber)?.intValue ?? -1
        XCTAssertEqual(after2, 1, "unchanged diagram reuses the cached SVG")

        // Changed source re-renders.
        await h.renderAndWait("```mermaid\nflowchart TD; A-->C\n```\n")
        let after3 = (await h.eval("window.__mermaidRenderCount") as? NSNumber)?.intValue ?? -1
        XCTAssertEqual(after3, 2, "changed diagram source re-renders")
    }
}
