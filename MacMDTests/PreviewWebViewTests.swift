import XCTest
import WebKit
@testable import MacMD

@MainActor
final class PreviewWebViewTests: XCTestCase {

    func testHandlerDocumentDirectorySetFromInput() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let preview = PreviewWebView(text: "", theme: ThemeController(),
                                     syncBridge: nil, documentDirectory: tempDir)
        let coordinator = preview.makeCoordinator()
        preview.applyState(to: coordinator)
        XCTAssertEqual(coordinator.handler.documentDirectory?.standardizedFileURL,
                       tempDir.standardizedFileURL)
    }

    func testBridgeInstallsPreviewDriveClosureOnAttach() {
        let bridge = ScrollSyncBridge()
        let preview = PreviewWebView(text: "", theme: ThemeController(),
                                     syncBridge: bridge, documentDirectory: nil)
        let coordinator = preview.makeCoordinator()
        preview.applyState(to: coordinator)
        XCTAssertNotNil(bridge.scrollPreviewToLine, "attach installs the editor-drives-preview closure")
    }

    func testShellMessagesRouteByNameAndRejectBadLines() {
        var toggled: [Int] = []
        var scrolled: [Int] = []
        let bridge = ScrollSyncBridge()
        bridge.scrollEditorToLine = { scrolled.append($0) }
        let preview = PreviewWebView(text: "", theme: ThemeController(), syncBridge: bridge,
                                     documentDirectory: nil, onToggleTask: { toggled.append($0) })
        let coordinator = preview.makeCoordinator()
        preview.applyState(to: coordinator)

        coordinator.receive(name: PreviewWebView.taskToggleMessageName, body: NSNumber(value: 3))
        coordinator.receive(name: PreviewWebView.taskToggleMessageName, body: "3")
        coordinator.receive(name: PreviewWebView.taskToggleMessageName, body: NSNumber(value: 0))
        coordinator.receive(name: PreviewWebView.scrollMessageName, body: NSNumber(value: 7))

        XCTAssertEqual(toggled, [3], "only a positive line number reaches the toggle")
        XCTAssertEqual(scrolled, [7], "scroll messages still drive the editor")
    }

    func testThemeCSSReachesDOM() async {
        let h = PreviewHarness()
        await h.load()

        // std.rgb has H1 light hex #C13F50.
        let suite = "PreviewWebViewTests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.set("std.rgb", forKey: ThemeSettings.selectedThemeKey)
        let theme = ThemeController(defaults: d)
        d.removePersistentDomain(forName: suite)

        let css = PreviewCSS.css(theme: theme)
        await h.eval("window.setThemeCSS(\(MarkdownRenderEngine.jsStringLiteral(css)))")
        let styleText = await h.eval("document.getElementById('macmd-theme').textContent") as? String
        XCTAssertNotNil(styleText?.range(of: "c13f50", options: .caseInsensitive),
                        "the injected theme CSS reaches the live style element")
    }
}

