import XCTest
@testable import MacMD

@MainActor
final class FormattingPrefTests: XCTestCase {
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: FormattingPref.key)
        super.tearDown()
    }

    func testDefaultsToOn() {
        UserDefaults.standard.removeObject(forKey: FormattingPref.key)
        XCTAssertTrue(FormattingPref.isOn)
    }

    func testSetPersistsAndReads() {
        FormattingPref.set(false)
        XCTAssertFalse(FormattingPref.isOn)
        FormattingPref.set(true)
        XCTAssertTrue(FormattingPref.isOn)
    }

    func testSetPostsNotification() {
        let exp = expectation(forNotification: FormattingPref.didChange, object: nil, handler: nil)
        FormattingPref.set(false)
        wait(for: [exp], timeout: 1.0)
    }

    func testShouldHighlightTruthTable() {
        XCTAssertTrue(FormattingPref.shouldHighlight(showFormatting: true, overSoftSizeLimit: false))
        XCTAssertFalse(FormattingPref.shouldHighlight(showFormatting: false, overSoftSizeLimit: false))
        XCTAssertFalse(FormattingPref.shouldHighlight(showFormatting: true, overSoftSizeLimit: true))
        XCTAssertFalse(FormattingPref.shouldHighlight(showFormatting: false, overSoftSizeLimit: true))
    }
}
