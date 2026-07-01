import XCTest
import WebKit
@testable import MacMD

@MainActor
final class PreviewWebViewTests: XCTestCase {

    func testHandlerDocumentDirectorySetFromInput() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let preview = PreviewWebView(text: "", theme: ThemeController(),
                                     topVisibleLine: nil, documentDirectory: tempDir)
        let coordinator = preview.makeCoordinator()
        preview.applyState(to: coordinator)
        XCTAssertEqual(coordinator.handler.documentDirectory?.standardizedFileURL,
                       tempDir.standardizedFileURL)
    }

    func testThemeCSSReachesDOM() async {
        let h = PreviewHarness()
        await h.load()

        // std.rgb has H1 light hex #C13F50.
        let suite = "PreviewWebViewTests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.set(Coloring.standard.rawValue, forKey: ThemeSettings.schemeKey)
        d.set("std.rgb", forKey: ThemeSettings.themeIdKey)
        let theme = ThemeController(defaults: d)
        d.removePersistentDomain(forName: suite)

        let css = PreviewCSS.css(theme: theme)
        await h.eval("window.setThemeCSS(\(PreviewWebView.jsStringLiteral(css)))")
        let styleText = await h.eval("document.getElementById('macmd-theme').textContent") as? String
        XCTAssertNotNil(styleText?.range(of: "c13f50", options: .caseInsensitive),
                        "the injected theme CSS reaches the live style element")
    }
}

