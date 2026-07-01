import XCTest
@testable import MacMD

@MainActor
final class HTMLExporterTests: XCTestCase {

    func testProducesSelfContainedHTMLWithInlineCSS() async {
        let html = await HTMLExporter.makeSelfContainedHTML(markdown: "# Hello\n\nWorld",
                                                            theme: ThemeController())

        XCTAssertTrue(html.contains("<h1"), "markdown-it rendered the heading")
        XCTAssertTrue(html.localizedCaseInsensitiveContains("Hello"))
        XCTAssertTrue(html.contains("<style"), "CSS is inlined")
        XCTAssertFalse(html.contains("<script"), "no script in the exported file")
        XCTAssertFalse(html.contains("<link"), "no external stylesheet")
        XCTAssertFalse(html.contains("macmd-resource:"), "the loader scheme is not carried into the output")

        // Precise external-reference guard. These resource-specific substrings are
        // used deliberately (not a blanket "http") so the M4 mermaid SVG namespace
        // xmlns="http://www.w3.org/2000/svg" does not later false-positive.
        for token in ["src=\"http", "href=\"http", "url(http", "@import", "file://"] {
            XCTAssertFalse(html.contains(token), "no external reference: \(token)")
        }
    }
}
