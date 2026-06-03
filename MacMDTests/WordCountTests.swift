import XCTest
@testable import MacMD

final class WordCountTests: XCTestCase {

    func testEmptyIsZero() {
        let s = WordCount.stats(for: "")
        XCTAssertEqual(s.words, 0)
        XCTAssertEqual(s.characters, 0)
    }

    func testTwoWords() {
        XCTAssertEqual(WordCount.stats(for: "hello world").words, 2)
    }

    func testCharacterCountCountsGraphemes() {
        XCTAssertEqual(WordCount.stats(for: "hello").characters, 5)
    }

    func testCharacterCountUsesGraphemeClusters() {
        // "e" + combining acute accent = 2 Unicode scalars but 1 grapheme cluster.
        XCTAssertEqual(WordCount.stats(for: "e\u{301}").characters, 1)
    }

    func testCollapsesWhitespaceRuns() {
        XCTAssertEqual(WordCount.stats(for: "  one   two\n\nthree  ").words, 3)
    }

    func testPunctuationNotCountedAsWords() {
        XCTAssertEqual(WordCount.stats(for: "yes! no? maybe.").words, 3)
    }

    func testCJKCountsAtLeastOneWord() {
        // ICU CJK word-break treats a run of ideographs as one token without a
        // dictionary, so assert >= 1 rather than a locale-dependent exact count.
        XCTAssertGreaterThanOrEqual(WordCount.stats(for: "日本語").words, 1)
    }

    func testReadingMinutesFloorsAtOneForAnyWords() {
        XCTAssertEqual(WordCount.readingMinutes(words: 1), 1)
    }

    func testReadingMinutesZeroForEmpty() {
        XCTAssertEqual(WordCount.readingMinutes(words: 0), 0)
    }

    func testReadingMinutesBoundaries() {
        XCTAssertEqual(WordCount.readingMinutes(words: 200), 1)
        XCTAssertEqual(WordCount.readingMinutes(words: 201), 2)
        XCTAssertEqual(WordCount.readingMinutes(words: 400), 2)
    }

    func testReadingMinutesHonorsCustomWpm() {
        XCTAssertEqual(WordCount.readingMinutes(words: 100, wpm: 100), 1)
        XCTAssertEqual(WordCount.readingMinutes(words: 150, wpm: 100), 2)
    }
}
