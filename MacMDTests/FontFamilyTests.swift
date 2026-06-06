import XCTest
import AppKit
@testable import MacMD

@MainActor
final class FontFamilyTests: XCTestCase {
    func testHasEightCuratedFamilies() {
        XCTAssertEqual(FontFamily.all.count, 8)
    }

    func testDefaultIsSystemMonospace() {
        XCTAssertEqual(FontFamily.default.id, "system-mono")
        XCTAssertTrue(FontFamily.default.isMonospace)
    }

    func testResolveUnknownIdFallsBackToDefault() {
        XCTAssertEqual(FontFamily.resolve(id: "garbage-not-a-font").id, FontFamily.default.id)
    }

    func testResolveKnownId() {
        XCTAssertEqual(FontFamily.resolve(id: "georgia").displayName, "Georgia")
    }

    func testEveryFamilyResolvesToUsableFontAtSize() {
        for fam in FontFamily.all {
            XCTAssertEqual(fam.font(size: 14).pointSize, 14, accuracy: 0.5, "\(fam.id) regular")
            XCTAssertEqual(fam.boldFont(size: 14).pointSize, 14, accuracy: 0.5, "\(fam.id) bold")
        }
    }

    func testMonospaceFlagMatchesFamily() {
        XCTAssertTrue(FontFamily.resolve(id: "menlo").isMonospace)
        XCTAssertFalse(FontFamily.resolve(id: "georgia").isMonospace)
    }

    func testBoldFontCarriesBoldTrait() {
        for fam in FontFamily.all {
            XCTAssertTrue(fam.boldFont(size: 14).fontDescriptor.symbolicTraits.contains(.bold),
                          "\(fam.id) bold should carry the bold trait")
        }
    }

    func testSystemMonospaceIsFixedPitch() {
        XCTAssertTrue(FontFamily.resolve(id: "system-mono").font(size: 14).isFixedPitch)
    }
}
