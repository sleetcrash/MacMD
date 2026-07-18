import XCTest
import AppKit
@testable import MacMD

@MainActor
final class PreviewCSSTests: XCTestCase {

    // Build a ThemeController from a throwaway defaults suite. The controller
    // reads the values in init, so the suite is removed immediately after.
    private func theme(themeId: String? = nil,
                       fontFamily: String? = nil, fontSize: Double? = nil) -> ThemeController {
        let suiteName = "PreviewCSSTests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suiteName)!
        if let themeId { d.set(themeId, forKey: ThemeSettings.selectedThemeKey) }
        if let fontFamily { d.set(fontFamily, forKey: ThemeSettings.fontFamilyKey) }
        if let fontSize { d.set(fontSize, forKey: FontSize.key) }
        let controller = ThemeController(defaults: d)
        d.removePersistentDomain(forName: suiteName)
        return controller
    }

    private func linesFor(_ css: String, class cls: String) -> String {
        css.split(separator: "\n").filter { $0.contains("html.\(cls) ") }.joined(separator: "\n")
    }

    private func rule(_ css: String, selector: String) -> String {
        css.split(separator: "\n").first { $0.contains(selector + " {") }.map(String.init) ?? ""
    }

    private func labelHex(under appearance: NSAppearance) -> String {
        var s = ""
        appearance.performAsCurrentDrawingAppearance { s = NSColor.labelColor.hexString }
        return s
    }

    func testHeadingColorsMatchResolvedPalette() {
        let css = PreviewCSS.css(theme: theme(themeId: "std.rgb"))
        // std.rgb H1 is light #C13F50 / dark #E86577.
        XCTAssertNotNil(linesFor(css, class: "aqua").range(of: "c13f50", options: .caseInsensitive))
        XCTAssertNotNil(linesFor(css, class: "darkAqua").range(of: "e86577", options: .caseInsensitive))
    }

    func testEmitsLightAndDarkBlocks() {
        let css = PreviewCSS.css(theme: theme(themeId: "std.rgb"))
        XCTAssertTrue(css.contains("html.aqua "))
        XCTAssertTrue(css.contains("html.darkAqua "))
    }

    func testDefaultSchemeHeadingsUseLabelColor() {
        // No scheme seeded -> Coloring.off (Default): headings use labelColor.
        let css = PreviewCSS.css(theme: theme())
        let expected = labelHex(under: NSAppearance(named: .aqua)!)
        XCTAssertTrue(rule(css, selector: "html.aqua h1").contains("color: \(expected)"),
                      "Default-scheme H1 must use labelColor, not a palette slot")
    }

    func testBodyFontStackFromFontFamily() {
        let serif = PreviewCSS.css(theme: theme(fontFamily: "new-york"))
        let mono = PreviewCSS.css(theme: theme(fontFamily: "system-mono"))
        XCTAssertTrue(bodyFontStack(serif).contains("serif"), "new-york emits a serif body stack")
        XCTAssertTrue(bodyFontStack(mono).contains("monospace"), "system-mono emits a monospace body stack")
        XCTAssertFalse(bodyFontStack(serif).contains("monospace"))
    }

    func testCodeBackgroundIsTranslucentRGBA() {
        let css = PreviewCSS.css(theme: theme())
        // code background is an rgba(...) at ~0.10 alpha, never a solid hex.
        XCTAssertNotNil(css.range(of: #"code[^{]*\{[^}]*background: rgba\(\d+, \d+, \d+, 0\.1\)"#,
                                  options: .regularExpression))
    }

    func testHeadingSizesMirrorEditor() {
        // base 16 -> H1 = 16+6 = 22, H6 = 16+1 = 17 (Theme.makeHeadingFonts uses base+(7-level)).
        let css = PreviewCSS.css(theme: theme(fontSize: 16))
        XCTAssertTrue(rule(css, selector: "html.aqua h1").contains("font-size: 22px"))
        XCTAssertTrue(rule(css, selector: "html.aqua h6").contains("font-size: 17px"))
    }

    private func bodyFontStack(_ css: String) -> String {
        guard let bodyRange = css.range(of: "html.aqua body {") else { return "" }
        let after = css[bodyRange.upperBound...]
        guard let ff = after.range(of: "font-family: ") else { return "" }
        let rest = after[ff.upperBound...]
        guard let semi = rest.firstIndex(of: ";") else { return "" }
        return String(rest[..<semi])
    }
}
