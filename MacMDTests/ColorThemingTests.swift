import XCTest
import AppKit
@testable import MacMD

final class ColorThemingTests: XCTestCase {

    // MARK: - Hex

    func testHexParsesSixDigits() {
        let c = NSColor(hex: "#C13F50")!.usingColorSpace(.sRGB)!
        XCTAssertEqual(c.redComponent, CGFloat(0xC1) / 255, accuracy: 0.001)
        XCTAssertEqual(c.greenComponent, CGFloat(0x3F) / 255, accuracy: 0.001)
        XCTAssertEqual(c.blueComponent, CGFloat(0x50) / 255, accuracy: 0.001)
    }

    func testHexAcceptsNoHashPrefix() {
        XCTAssertEqual(NSColor(hex: "2E86AB")?.hexString, "#2E86AB")
    }

    func testHexRejectsMalformed() {
        XCTAssertNil(NSColor(hex: "#12"))
        XCTAssertNil(NSColor(hex: "ZZZZZZ"))
    }

    func testHexStringRoundTrips() {
        XCTAssertEqual(NSColor(hex: "#A86FE0")?.hexString, "#A86FE0")
    }
}
