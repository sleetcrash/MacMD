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

    func testStripsExternalImageReferences() async {
        // A hostile remote image must not survive as a live reference (a tracking
        // beacon that fetches when the exported file is opened elsewhere).
        let md = "![beacon](https://attacker.example/track.png)\n\n![proto](//attacker.example/p.png)"
        let html = await HTMLExporter.makeSelfContainedHTML(markdown: md, theme: ThemeController())
        XCTAssertFalse(html.contains("attacker.example"), "remote image reference stripped")
        XCTAssertFalse(html.contains("src=\"http"))
        XCTAssertFalse(html.contains("src=\"//"))
    }

    func testInlinesContainedLocalImage() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        // A minimal 1x1 PNG.
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==")!
        try png.write(to: dir.appendingPathComponent("pic.png"))

        let html = await HTMLExporter.makeSelfContainedHTML(markdown: "![](pic.png)", theme: ThemeController(),
                                                            documentDirectory: dir)
        XCTAssertTrue(html.contains("data:image/png;base64,"), "a contained local image is inlined")
        XCTAssertFalse(html.contains("src=\"pic.png\""))
    }

    func testEscapingLocalImageIsStripped() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let docDir = root.appendingPathComponent("doc")
        try FileManager.default.createDirectory(at: docDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("secret".utf8).write(to: root.appendingPathComponent("secret.png"))

        let html = await HTMLExporter.makeSelfContainedHTML(markdown: "![](../secret.png)", theme: ThemeController(),
                                                            documentDirectory: docDir)
        XCTAssertFalse(html.contains("secret.png"), "an escaping image path is dropped, not inlined")
    }

    func testSuggestedFilename() {
        XCTAssertEqual(HTMLExporter.suggestedFilename(representedURL: URL(fileURLWithPath: "/tmp/Notes.md"),
                                                      windowTitle: "Notes.md"), "Notes.html")
        XCTAssertEqual(HTMLExporter.suggestedFilename(representedURL: nil, windowTitle: "Untitled"), "Untitled.html")
    }
}
