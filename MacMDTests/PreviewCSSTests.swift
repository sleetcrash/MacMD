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

    // MARK: - Mermaid palette variables

    func testMermaidSeriesFollowsPaletteHeadings() {
        let css = PreviewCSS.css(theme: theme(themeId: "std.rgb"))
        // std.rgb: H1 #C13F50 / H2 #2E8049 / H3 #2E86AB on the light side.
        XCTAssertEqual(mermaidVar(css, class: "aqua", name: "--mmd-series-1").lowercased(), "#c13f50")
        XCTAssertEqual(mermaidVar(css, class: "aqua", name: "--mmd-series-2").lowercased(), "#2e8049")
        XCTAssertEqual(mermaidVar(css, class: "aqua", name: "--mmd-series-3").lowercased(), "#2e86ab")
    }

    func testMermaidSeriesCyclesWithoutRepeatingAColor() {
        let css = PreviewCSS.css(theme: theme(themeId: "std.rgb"))
        let first = mermaidVar(css, class: "aqua", name: "--mmd-series-1")
        let fourth = mermaidVar(css, class: "aqua", name: "--mmd-series-4")
        XCTAssertFalse(first.isEmpty)
        XCTAssertNotEqual(first, fourth, "a second cycle shifts toward the background rather than repeating")
        XCTAssertFalse(mermaidVar(css, class: "aqua", name: "--mmd-series-12").isEmpty, "all 12 slots are emitted")
    }

    func testMermaidSeriesIsNeutralUnderDefaultScheme() {
        // Default scheme has no palette: the ramp comes from the body color, so
        // every slot is a shade of it rather than an unrelated mermaid default.
        let css = PreviewCSS.css(theme: theme())
        let one = mermaidVar(css, class: "darkAqua", name: "--mmd-series-1")
        let two = mermaidVar(css, class: "darkAqua", name: "--mmd-series-2")
        XCTAssertTrue(isGray(one), "expected a neutral shade, got \(one)")
        XCTAssertTrue(isGray(two), "expected a neutral shade, got \(two)")
        XCTAssertNotEqual(one, two, "the ramp steps between slots")
    }

    func testMermaidTextMatchesBodyColor() {
        let css = PreviewCSS.css(theme: theme(themeId: "std.rgb"))
        for cls in ["aqua", "darkAqua"] {
            let appearance = NSAppearance(named: cls == "aqua" ? .aqua : .darkAqua)!
            XCTAssertEqual(mermaidVar(css, class: cls, name: "--mmd-text").lowercased(),
                           labelHex(under: appearance).lowercased(),
                           "diagram labels take the body color in the \(cls) block")
        }
    }

    func testMermaidBackgroundMatchesThemeBackground() {
        // tint.cream is a background-carrying theme: the diagram background must
        // follow it, not the default editor background.
        let css = PreviewCSS.css(theme: theme(themeId: "tint.cream"))
        let bg = mermaidVar(css, class: "aqua", name: "--mmd-bg").lowercased()
        let expected = Palette.tintThemes.first { $0.id == "tint.cream" }?.background.light.lowercased()
        XCTAssertEqual(bg, expected)
    }

    /// The value of one custom property inside a `html.<class> { ... }` block.
    private func mermaidVar(_ css: String, class cls: String, name: String) -> String {
        guard let line = css.split(separator: "\n").first(where: { $0.hasPrefix("html.\(cls) { --mmd-") }),
              let start = line.range(of: "\(name): ") else { return "" }
        let rest = line[start.upperBound...]
        guard let semi = rest.firstIndex(of: ";") else { return "" }
        return String(rest[..<semi])
    }

    private func isGray(_ hex: String) -> Bool {
        guard hex.count == 7, hex.hasPrefix("#") else { return false }
        let comps = stride(from: 1, to: 7, by: 2).compactMap { i -> Int? in
            let start = hex.index(hex.startIndex, offsetBy: i)
            return Int(hex[start..<hex.index(start, offsetBy: 2)], radix: 16)
        }
        guard comps.count == 3 else { return false }
        return abs(comps[0] - comps[1]) <= 2 && abs(comps[1] - comps[2]) <= 2
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
