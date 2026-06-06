import XCTest
@testable import MacMD

@MainActor
final class CursorStyleTests: XCTestCase {
    func testAllCasesCount() {
        XCTAssertEqual(CursorStyle.allCases.count, 3)
    }

    func testRawValuesRoundTrip() {
        for s in CursorStyle.allCases {
            XCTAssertEqual(CursorStyle(rawValue: s.rawValue), s)
        }
    }

    func testDisplayNames() {
        XCTAssertEqual(CursorStyle.bar.displayName, "Bar")
        XCTAssertEqual(CursorStyle.block.displayName, "Block")
        XCTAssertEqual(CursorStyle.underline.displayName, "Underline")
    }

    func testBlockWidthUsesGlyphWhenPositive() {
        XCTAssertEqual(CursorGeometry.blockWidth(glyphWidth: 8.5, fallback: 6), 8.5)
    }

    func testBlockWidthFallsBackWhenZero() {
        XCTAssertEqual(CursorGeometry.blockWidth(glyphWidth: 0, fallback: 6), 6)
    }

    func testBlockWidthFallsBackWhenNegative() {
        XCTAssertEqual(CursorGeometry.blockWidth(glyphWidth: -1, fallback: 7), 7)
    }

    // MARK: - Theme cursor state

    func testThemeDefaultsToBarBlinkOn() {
        Theme.setCursor(style: .bar, blink: true)
        XCTAssertEqual(Theme.cursorStyle, .bar)
        XCTAssertTrue(Theme.cursorBlink)
    }

    func testSetCursorReportsChange() {
        Theme.setCursor(style: .bar, blink: true)
        XCTAssertTrue(Theme.setCursor(style: .block, blink: true))
        XCTAssertFalse(Theme.setCursor(style: .block, blink: true))
        Theme.setCursor(style: .bar, blink: true)   // reset for other suites
    }
}
