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
}
