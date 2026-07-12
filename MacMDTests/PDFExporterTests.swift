import XCTest
@testable import MacMD

@MainActor
final class PDFExporterTests: XCTestCase {

    func testSuggestedFilenameCarriesPDFExtension() {
        XCTAssertEqual(HTMLExporter.suggestedFilename(representedURL: URL(fileURLWithPath: "/tmp/Notes.md"),
                                                      windowTitle: nil, ext: "pdf"), "Notes.pdf")
        XCTAssertEqual(HTMLExporter.suggestedFilename(representedURL: nil, windowTitle: nil, ext: "pdf"),
                       "Untitled.pdf")
    }

    func testMakePDFProducesAPDFWithTheThemeBackground() async {
        let suite = "PDFExporterTests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.set(AppAppearance.dark.rawValue, forKey: ThemeSettings.appearanceKey)
        let theme = ThemeController(defaults: d)
        d.removePersistentDomain(forName: suite)

        let data = await PDFExporter.makePDF(markdown: "# Title\n\nBody text.\n", theme: theme)
        XCTAssertNotNil(data)
        guard let data else { return }
        XCTAssertGreaterThan(data.count, 500, "a rendered page is never near-empty")
        XCTAssertEqual(String(data: data.prefix(5), encoding: .ascii), "%PDF-")
    }
}
