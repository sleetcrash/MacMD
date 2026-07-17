import XCTest
@testable import MacMD

@MainActor
final class EditingPrefsTests: XCTestCase {
    // The test host is the real app, so UserDefaults.standard is the user's
    // live prefs domain. Snapshot the touched keys and RESTORE them (not just
    // remove), so a suite run never resets prefs the user set on purpose.
    private static let keys = [SpellingPref.spellingKey, SpellingPref.grammarKey]
    private var saved: [String: Any] = [:]

    override func setUp() {
        super.setUp()
        for key in Self.keys {
            if let value = UserDefaults.standard.object(forKey: key) { saved[key] = value }
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    override func tearDown() {
        for key in Self.keys {
            if let value = saved[key] {
                UserDefaults.standard.set(value, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        saved = [:]
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
}
