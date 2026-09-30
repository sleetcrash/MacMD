import XCTest
import AppKit
@testable import MacMD

@MainActor
final class ThemeFontTests: XCTestCase {
    override func tearDown() {
        Theme.setEditorFontFamily(.default)
        Theme.setEditorFontSize(FontSize.standard)
        super.tearDown()
    }

    func testDefaultEditorFontIsFixedPitch() {
        Theme.setEditorFontFamily(.default)
        XCTAssertTrue(Theme.editorFont.isFixedPitch)
    }

    func testSettingProportionalFamilyChangesEditorFont() {
        XCTAssertTrue(Theme.setEditorFontFamily(FontFamily.resolve(id: "georgia")))
        XCTAssertFalse(Theme.editorFont.isFixedPitch)
    }

    func testSettingSameFamilyReturnsFalse() {
        Theme.setEditorFontFamily(.default)
        XCTAssertFalse(Theme.setEditorFontFamily(.default))
    }

    func testCodeFontStaysMonospaceUnderProportionalFamily() {
        Theme.setEditorFontFamily(FontFamily.resolve(id: "georgia"))
        XCTAssertTrue(Theme.codeFont.isFixedPitch)
    }

    func testHeadingFontsAreBoldForProportionalFamily() {
        Theme.setEditorFontFamily(FontFamily.resolve(id: "georgia"))
        for level in 1...6 {
            XCTAssertTrue(Theme.headingFont(level: level).fontDescriptor.symbolicTraits.contains(.bold),
                          "level \(level)")
        }
    }

    func testHeadingSizesScaleWithLevel() {
        Theme.setEditorFontSize(14)
        Theme.setEditorFontFamily(.default)
        XCTAssertEqual(Theme.headingFont(level: 1).pointSize, 25)
        XCTAssertEqual(Theme.headingFont(level: 2).pointSize, 21)
        XCTAssertEqual(Theme.headingFont(level: 3).pointSize, 18)
        XCTAssertEqual(Theme.headingFont(level: 4).pointSize, 15)
        XCTAssertEqual(Theme.headingFont(level: 5).pointSize, 14)
        XCTAssertEqual(Theme.headingFont(level: 6).pointSize, 14)
    }

    func testCodeFontTracksSize() {
        Theme.setEditorFontSize(20)
        XCTAssertEqual(Theme.codeFont.pointSize, 20, accuracy: 0.5)
    }
}
