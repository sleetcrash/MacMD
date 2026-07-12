import XCTest
@testable import MacMD

@MainActor
final class LineNumbersPrefTests: XCTestCase {
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: LineNumbersPref.key)
        super.tearDown()
    }

    func testDefaultsToOn() {
        UserDefaults.standard.removeObject(forKey: LineNumbersPref.key)
        XCTAssertTrue(LineNumbersPref.isOn)
    }

    func testSetPersistsAndReads() {
        LineNumbersPref.set(false)
        XCTAssertFalse(LineNumbersPref.isOn)
        LineNumbersPref.set(true)
        XCTAssertTrue(LineNumbersPref.isOn)
    }

    func testSetPostsNotification() {
        let exp = expectation(forNotification: LineNumbersPref.didChange, object: nil, handler: nil)
        LineNumbersPref.set(false)
        wait(for: [exp], timeout: 1.0)
    }
}
