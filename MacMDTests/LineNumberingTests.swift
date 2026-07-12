import XCTest
@testable import MacMD

@MainActor
final class LineNumberingTests: XCTestCase {
    private func num(_ index: Int, _ s: String) -> Int {
        LineNumbering.lineNumber(forCharacterIndex: index, in: s as NSString)
    }

    func testFirstLineIsOne() { XCTAssertEqual(num(0, "abc\ndef"), 1) }
    func testIndexInFirstLine() { XCTAssertEqual(num(2, "abc\ndef"), 1) }
    func testIndexAfterFirstNewlineIsLineTwo() { XCTAssertEqual(num(4, "abc\ndef"), 2) }
    func testFiveLines() { XCTAssertEqual(num(8, "a\nb\nc\nd\ne"), 5) }
    func testClampsBeyondEnd() { XCTAssertEqual(num(999, "a\nb"), 2) }
    func testEmptyStringIsOne() { XCTAssertEqual(num(0, ""), 1) }
    func testTrailingNewlineCountsNextLine() { XCTAssertEqual(num(2, "a\n"), 2) }

    // lineCount(in:) is the fast total-line path; it must agree with the
    // per-character helper at the end of the string for every shape.
    func testLineCountMatchesLineNumberAtEnd() {
        for s in ["", "a", "a\nb", "a\nb\nc\nd\ne", "a\n", "a\n\nb", "\n\n\n"] {
            XCTAssertEqual(LineNumbering.lineCount(in: s),
                           num((s as NSString).length, s),
                           "lineCount disagreed for \(s.debugDescription)")
        }
    }

    func testLineCountEmptyIsOne() { XCTAssertEqual(LineNumbering.lineCount(in: ""), 1) }
    func testLineCountTrailingNewline() { XCTAssertEqual(LineNumbering.lineCount(in: "a\n"), 2) }

    // characterIndex(forLine:) is the inverse map, used by preview-to-editor
    // scroll sync.
    private func start(_ line: Int, _ s: String) -> Int {
        LineNumbering.characterIndex(forLine: line, in: s as NSString)
    }

    func testCharacterIndexFirstLineIsZero() { XCTAssertEqual(start(1, "abc\ndef"), 0) }
    func testCharacterIndexSecondLine() { XCTAssertEqual(start(2, "a\nbb\nccc"), 2) }
    func testCharacterIndexThirdLine() { XCTAssertEqual(start(3, "a\nbb\nccc"), 5) }
    func testCharacterIndexClampsToLastLine() { XCTAssertEqual(start(99, "a\nbb\nccc"), 5) }
    func testCharacterIndexTrailingEmptyLine() { XCTAssertEqual(start(2, "a\n"), 2) }
    func testCharacterIndexEmptyString() { XCTAssertEqual(start(3, ""), 0) }

    func testCharacterIndexRoundTripsWithLineNumber() {
        let s = "one\ntwo\n\nfour\nfive\n"
        for line in 1...LineNumbering.lineCount(in: s) {
            XCTAssertEqual(num(start(line, s), s), line, "round trip failed at line \(line)")
        }
    }
}
