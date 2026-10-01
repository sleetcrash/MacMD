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

    // MARK: - Dark-theme colors

    private static let darkThemeCSS = "html.darkAqua { --mmd-bg: #101014; --mmd-text: #eeeeee; --mmd-surface: #26262c; --mmd-line: #8a8a95; --mmd-series-1: #3ec6ff; --mmd-series-2: #ff4fb2; --mmd-series-3: #eccb00; }"

    private func loadDarkTheme() async -> PreviewHarness {
        let h = PreviewHarness()
        await h.load()
        await h.eval("window.setThemeCSS('\(Self.darkThemeCSS)')")
        await h.eval("window.setAppearance('darkAqua')")
        return h
    }

    /// The computed `property` of every element matching `selector` inside the
    /// rendered diagrams, as mermaid's own stylesheet resolves it (`rgb(r, g, b)`).
    private func computedColors(_ h: PreviewHarness, _ selector: String, property: String = "fill") async -> [String] {
        let js = "Array.prototype.map.call(document.querySelectorAll('.mermaid-diagram \(selector)'), function (el) { return getComputedStyle(el).\(property); })"
        return (await h.eval(js) as? [String] ?? []).filter { $0 != "none" }
    }

    private func channels(_ color: String) -> [Double] {
        if color.hasPrefix("#") {
            let hex = color.dropFirst()
            return stride(from: 0, to: 6, by: 2).map {
                Double(Int(hex[hex.index(hex.startIndex, offsetBy: $0)..<hex.index(hex.startIndex, offsetBy: $0 + 2)], radix: 16) ?? 0)
            }
        }
        return color.components(separatedBy: CharacterSet(charactersIn: "(), ")).compactMap(Double.init)
    }

    /// WCAG contrast ratio between two colors (`rgb(...)` or `#rrggbb`).
    private func contrast(_ a: String, _ b: String) -> Double {
        func luminance(_ c: [Double]) -> Double {
            let lin = c.prefix(3).map { ch -> Double in
                let s = ch / 255
                return s <= 0.03928 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * lin[0] + 0.7152 * lin[1] + 0.0722 * lin[2]
        }
        let la = luminance(channels(a)), lb = luminance(channels(b))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    private func maxChannelDistance(_ a: String, _ b: String) -> Double {
        zip(channels(a).prefix(3), channels(b).prefix(3)).map { abs($0 - $1) }.max() ?? 255
    }

    func testErAttributeRowsReadOnADarkTheme() async {
        let h = await loadDarkTheme()
        await h.renderAndWait("```mermaid\nerDiagram\n    AUTHOR {\n        string name\n        string handle\n        int posts\n    }\n```\n")

        let dark = await h.eval("window.__mermaidConfig.themeVariables.darkMode") as? NSNumber
        XCTAssertEqual(dark?.boolValue, true, "the base theme is told the page is dark")

        let fills = await computedColors(h, ".node rect, .node path")
        XCTAssertFalse(fills.isEmpty, "the entity box and its attribute rows have fills")
        for fill in fills {
            XCTAssertGreaterThanOrEqual(contrast(fill, "#eeeeee"), 3, "row fill \(fill) must carry the body text")
        }
    }

    func testSequenceAutonumbersReadOnTheirDiscs() async {
        let h = await loadDarkTheme()
        await h.renderAndWait("```mermaid\nsequenceDiagram\n    autonumber\n    A->>B: hi\n    B-->>A: hello\n```\n")

        let digits = await computedColors(h, "text.sequenceNumber")
        XCTAssertFalse(digits.isEmpty, "autonumber digits are drawn")
        for digit in digits {
            XCTAssertGreaterThanOrEqual(contrast(digit, "#8a8a95"), 3, "digit color \(digit) must read on the line-colored disc")
        }
    }

    func testGitBranchesTakeTheSeriesColorsOnADarkTheme() async {
        let h = await loadDarkTheme()
        await h.renderAndWait("```mermaid\ngitGraph\n    commit\n    branch feature\n    checkout feature\n    commit\n    checkout main\n    merge feature\n```\n")

        // The commit-to-commit connectors (the dashed guide lines are `.branch`).
        let strokes = Set(await computedColors(h, "path.arrow", property: "stroke"))
        XCTAssertEqual(strokes.count, 2, "main and feature connectors are drawn in two colors: \(strokes)")
        for stroke in strokes {
            let onSeries = min(maxChannelDistance(stroke, "#3ec6ff"), maxChannelDistance(stroke, "#ff4fb2"))
            XCTAssertLessThanOrEqual(onSeries, 3, "a connector takes a series color as published, not a darkened shade: \(stroke)")
        }

        let labels = await computedColors(h, ".branchLabel text")
        XCTAssertEqual(labels.count, 2, "both branch labels are drawn")
        for label in labels {
            XCTAssertLessThanOrEqual(maxChannelDistance(label, "#101014"), 3, "a label on a series-colored tag takes the background color: \(label)")
        }
    }

    func testGanttFollowsTheContentColumnWidth() async {
        let h = PreviewHarness()   // 480pt wide: a 424px content column after the body padding
        await h.load()
        await h.renderAndWait("```mermaid\ngantt\n    dateFormat YYYY-MM-DD\n    section A\n    Task :a1, 2026-10-01, 5d\n```\n")
        let widthJS = "parseFloat(document.querySelector('.mermaid-diagram svg').getAttribute('viewBox').split(' ')[2])"
        let narrow = (await h.eval(widthJS) as? NSNumber)?.doubleValue ?? 0
        XCTAssertEqual(narrow, 424, accuracy: 1)

        // A wider pane re-lays the gantt out to the (760px max) column.
        h.webView.frame = CGRect(x: 0, y: 0, width: 900, height: 640)
        var wide = narrow
        for _ in 0..<120 {
            wide = (await h.eval(widthJS) as? NSNumber)?.doubleValue ?? 0
            if wide != narrow { break }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertEqual(wide, 760, accuracy: 1, "the gantt re-rendered at the new column width")
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
