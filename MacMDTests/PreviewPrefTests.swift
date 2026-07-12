import XCTest
@testable import MacMD

final class PaneModePrefTests: XCTestCase {

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: PaneModePref.key)
        UserDefaults.standard.removeObject(forKey: PaneModePref.legacyKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: PaneModePref.key)
        UserDefaults.standard.removeObject(forKey: PaneModePref.legacyKey)
        super.tearDown()
    }

    func testDefaultsToEditorOnly() {
        XCTAssertEqual(PaneModePref.mode, .editor, "documents open editor-only by default")
        XCTAssertFalse(PaneModePref.previewVisible)
    }

    func testSetRoundTripsAndPostsDidChange() {
        let exp = expectation(forNotification: PaneModePref.didChange, object: nil)
        PaneModePref.set(.split)
        wait(for: [exp], timeout: 1.0)
        XCTAssertEqual(PaneModePref.mode, .split)
        XCTAssertTrue(PaneModePref.previewVisible)
        PaneModePref.set(.preview)
        XCTAssertEqual(PaneModePref.mode, .preview)
        XCTAssertTrue(PaneModePref.previewVisible)
        PaneModePref.set(.editor)
        XCTAssertEqual(PaneModePref.mode, .editor)
    }

    func testMigrateFastCutsLegacyShowPreview() {
        UserDefaults.standard.set(true, forKey: PaneModePref.legacyKey)
        PaneModePref.migrate()
        XCTAssertEqual(PaneModePref.mode, .split, "showPreview=true becomes the split layout")
        XCTAssertNil(UserDefaults.standard.object(forKey: PaneModePref.legacyKey), "legacy key is deleted")
    }

    func testMigrateNeverOverwritesAnExistingMode() {
        PaneModePref.set(.preview)
        UserDefaults.standard.set(true, forKey: PaneModePref.legacyKey)
        PaneModePref.migrate()
        XCTAssertEqual(PaneModePref.mode, .preview)
    }
}
