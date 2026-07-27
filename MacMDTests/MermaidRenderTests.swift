import XCTest
import WebKit
@testable import MacMD

@MainActor
final class MermaidRenderTests: XCTestCase {

    /// The page's rendered markup with `<script>` text stripped: the shell's own
    /// inline JS quotes mermaid's error string in a comment, which would otherwise
    /// match any assertion looking for a leftover error graphic.
    private static let renderedBodyJS = """
    (function () {
      var copy = document.body.cloneNode(true);
      var scripts = copy.querySelectorAll("script");
      for (var i = 0; i < scripts.length; i++) { scripts[i].remove(); }
      return copy.innerHTML;
    })()
    """

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

    func testDiagramColorsComeFromThemeVariables() async {
        let h = PreviewHarness()
        await h.load()
        await h.eval("window.setThemeCSS('html.darkAqua { --mmd-bg: #101014; --mmd-text: #eeeeee; --mmd-surface: #26262c; --mmd-line: #8a8a95; --mmd-series-1: #3ec6ff; --mmd-series-2: #ff4fb2; --mmd-series-3: #eccb00; }')")
        await h.eval("window.setAppearance('darkAqua')")
        await h.renderAndWait("```mermaid\npie showData\n    \"A\" : 50\n    \"B\" : 30\n    \"C\" : 20\n```\n")

        let theme = await h.eval("window.__mermaidConfig && window.__mermaidConfig.theme") as? String
        XCTAssertEqual(theme, "base", "the app palette drives mermaid through the base theme")

        let svg = (await h.eval("document.querySelector('.mermaid-diagram').innerHTML") as? String ?? "").lowercased()
        XCTAssertTrue(svg.contains("#3ec6ff"), "the first pie slice takes the theme's first series color")
        XCTAssertTrue(svg.contains("#ff4fb2"), "the second slice takes the second series color")
        XCTAssertFalse(svg.contains("#eceff1"), "mermaid's stock default palette is gone")
    }

    func testThemeChangeRerendersExistingDiagrams() async {
        let h = PreviewHarness()
        await h.load()
        await h.eval("window.setThemeCSS('html.darkAqua { --mmd-series-1: #3ec6ff; }')")
        await h.eval("window.setAppearance('darkAqua')")
        await h.renderAndWait("```mermaid\npie\n    \"A\" : 50\n    \"B\" : 50\n```\n")
        let before = (await h.eval("document.querySelector('.mermaid-diagram').innerHTML") as? String ?? "").lowercased()
        XCTAssertTrue(before.contains("#3ec6ff"))

        // A theme switch moves colors mermaid already baked into the SVG.
        let pass = (await h.eval("window.__mermaidThemePass || 0") as? NSNumber)?.intValue ?? 0
        await h.eval("window.setThemeCSS('html.darkAqua { --mmd-series-1: #ff8800; }')")
        for _ in 0..<120 {
            let now = (await h.eval("window.__mermaidThemePass || 0") as? NSNumber)?.intValue ?? 0
            if now > pass { break }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        let after = (await h.eval("document.querySelector('.mermaid-diagram').innerHTML") as? String ?? "").lowercased()
        XCTAssertTrue(after.contains("#ff8800"), "the diagram re-rendered under the new theme")
        XCTAssertFalse(after.contains("#3ec6ff"), "the stale color is gone")
    }

    /// Typing a diagram means rendering half-written ones on every keystroke.
    /// Mermaid appends its own error graphic ("Syntax error in text") to the page
    /// when a parse fails, OUTSIDE the content div, so those survive the next
    /// render and pile up at the bottom of the preview.
    func testFailedDiagramLeavesNoErrorGraphicInThePage() async {
        let h = PreviewHarness()
        await h.load()
        // Two half-typed diagrams, as they exist mid-keystroke.
        await h.renderAndWait("```mermaid\nflowchart LR\n    A[Write] -->\n```\n")
        await h.renderAndWait("```mermaid\nsequenceDiagram\n    Editor->>\n```\n")

        let body = (await h.eval(Self.renderedBodyJS) as? String ?? "")
        XCTAssertFalse(body.contains("Syntax error in text"),
                       "a failed diagram must not leave mermaid's error graphic in the page")

        // The fence stays as code, so the writer still sees what they are typing.
        let leftover = (await h.eval("document.querySelectorAll('code.language-mermaid').length") as? NSNumber)?.intValue ?? -1
        XCTAssertEqual(leftover, 1, "the unparseable fence stays a code block")
    }

    /// The live sequence: Swift pushes theme CSS and appearance, then the document
    /// text, in the same turn. The theme refresh and the content render must not
    /// call mermaid concurrently, and no failure may leave mermaid's error graphic
    /// ("Syntax error in text") sitting in the page.
    func testConcurrentThemeRefreshAndRenderLeaveNoErrorGraphic() async {
        let h = PreviewHarness()
        await h.load()
        let doc = """
        ```mermaid
        flowchart LR
            A[Write] --> B{Preview}
            B -->|split| C[Editor and preview]
        ```

        ```mermaid
        pie showData
            title Time in Editor
            "Writing" : 45
            "Theming" : 20
        ```

        ```mermaid
        sequenceDiagram
            Editor->>Preview: keystroke
            Preview->>Editor: scroll position
        ```

        """
        // No await between these: the refresh is in flight when the render starts.
        await h.eval("window.setThemeCSS('html.darkAqua { --mmd-series-1: #3ec6ff; }'); window.setAppearance('darkAqua'); \(MarkdownRenderEngine.renderInvocation(markdown: doc))")

        for _ in 0..<120 {
            let done = (await h.eval("(window.__renderComplete || 0) > 0 && !document.querySelector('code.language-mermaid')") as? NSNumber)?.boolValue ?? false
            if done { break }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        try? await Task.sleep(nanoseconds: 500_000_000)   // let any late refresh land

        let body = (await h.eval(Self.renderedBodyJS) as? String ?? "")
        XCTAssertFalse(body.contains("Syntax error in text"),
                       "a concurrent theme refresh must not leave mermaid's error graphic in the page")
        let svgCount = (await h.eval("document.querySelectorAll('.mermaid-diagram svg').length") as? NSNumber)?.intValue ?? 0
        XCTAssertEqual(svgCount, 3, "all three diagrams survive the overlap")
    }

    func testDuplicateDiagramsGetDistinctIds() async {
        let h = PreviewHarness()
        await h.load()
        let block = "```mermaid\nflowchart TD; A-->B\n```\n"
        await h.renderAndWait("\(block)\n\(block)")   // two identical diagrams in one document

        let svgCount = (await h.eval("document.querySelectorAll('svg').length") as? NSNumber)?.intValue ?? 0
        XCTAssertEqual(svgCount, 2, "both identical diagrams render")
        let uniqueIds = (await h.eval("(function(){var s=document.querySelectorAll('svg');var ids={};for(var i=0;i<s.length;i++){ids[s[i].id]=1;}return Object.keys(ids).length;})()") as? NSNumber)?.intValue ?? 0
        XCTAssertEqual(uniqueIds, 2, "the two rendered SVGs carry distinct ids (no malformed duplicate id)")
    }
}
