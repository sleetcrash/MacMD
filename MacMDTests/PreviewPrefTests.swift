import XCTest
@testable import MacMD

final class PreviewPrefTests: XCTestCase {

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: PreviewPref.key)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: PreviewPref.key)
        super.tearDown()
    }

    func testDefaultsToHidden() {
        XCTAssertFalse(PreviewPref.isVisible, "preview is opt-in, hidden by default")
    }

    func testIsVisibleRoundTrips() {
        PreviewPref.isVisible = true
        XCTAssertTrue(PreviewPref.isVisible)
        PreviewPref.isVisible = false
        XCTAssertFalse(PreviewPref.isVisible)
    }

    func testSettingIsVisiblePostsDidChange() {
        let exp = expectation(forNotification: PreviewPref.didChange, object: nil)
        PreviewPref.isVisible = true
        wait(for: [exp], timeout: 1.0)
    }
}
