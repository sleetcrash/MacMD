import XCTest
@testable import MacMD

@MainActor
final class EditingPrefsTests: XCTestCase {
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: SpellingPref.spellingKey)
        UserDefaults.standard.removeObject(forKey: SpellingPref.grammarKey)
        UserDefaults.standard.removeObject(forKey: NewWindowSize.widthKey)
        UserDefaults.standard.removeObject(forKey: NewWindowSize.heightKey)
        super.tearDown()
    }

    // MARK: - SpellingPref

    func testSpellingDefaultsToOn() {
        UserDefaults.standard.removeObject(forKey: SpellingPref.spellingKey)
        XCTAssertTrue(SpellingPref.checkSpelling)
    }

    func testGrammarDefaultsToOff() {
        UserDefaults.standard.removeObject(forKey: SpellingPref.grammarKey)
        XCTAssertFalse(SpellingPref.checkGrammar)
    }

    func testSetSpellingPersistsAndReads() {
        SpellingPref.setCheckSpelling(false)
        XCTAssertFalse(SpellingPref.checkSpelling)
        SpellingPref.setCheckSpelling(true)
        XCTAssertTrue(SpellingPref.checkSpelling)
    }

    func testSetGrammarPersistsAndReads() {
        SpellingPref.setCheckGrammar(true)
        XCTAssertTrue(SpellingPref.checkGrammar)
        SpellingPref.setCheckGrammar(false)
        XCTAssertFalse(SpellingPref.checkGrammar)
    }

    func testSetSpellingPostsNotification() {
        let exp = expectation(forNotification: SpellingPref.didChange, object: nil, handler: nil)
        SpellingPref.setCheckSpelling(false)
        wait(for: [exp], timeout: 1.0)
    }

    func testSetGrammarPostsNotification() {
        let exp = expectation(forNotification: SpellingPref.didChange, object: nil, handler: nil)
        SpellingPref.setCheckGrammar(true)
        wait(for: [exp], timeout: 1.0)
    }

    // MARK: - NewWindowSize

    func testSizeDefaults() {
        UserDefaults.standard.removeObject(forKey: NewWindowSize.widthKey)
        UserDefaults.standard.removeObject(forKey: NewWindowSize.heightKey)
        XCTAssertEqual(NewWindowSize.width, 760)
        XCTAssertEqual(NewWindowSize.height, 680)
    }

    func testSetPersistsRoundedValues() {
        NewWindowSize.set(width: 800.6, height: 600.4)
        XCTAssertEqual(NewWindowSize.width, 801)
        XCTAssertEqual(NewWindowSize.height, 600)
    }

    func testClampBounds() {
        XCTAssertEqual(NewWindowSize.clampWidth(10), NewWindowSize.minWidth)
        XCTAssertEqual(NewWindowSize.clampHeight(10), NewWindowSize.minHeight)
        XCTAssertEqual(NewWindowSize.clampWidth(99999), NewWindowSize.maxWidth)
        XCTAssertEqual(NewWindowSize.clampHeight(99999), NewWindowSize.maxHeight)
    }

    func testStoredOutOfRangeValueReadsClamped() {
        UserDefaults.standard.set(12.0, forKey: NewWindowSize.widthKey)
        UserDefaults.standard.set(90000.0, forKey: NewWindowSize.heightKey)
        XCTAssertEqual(NewWindowSize.width, NewWindowSize.minWidth)
        XCTAssertEqual(NewWindowSize.height, NewWindowSize.maxHeight)
    }
}
