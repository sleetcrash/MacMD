import XCTest
import AppKit
@testable import MacMD

final class TaskListInteractionTests: XCTestCase {

    func testToggleReplacesSpaceWithX() {
        let storage = NSTextStorage(string: "- [ ] one")
        let highlighter = MarkdownHighlighter()
        let ranges = highlighter.taskCheckboxRanges(in: storage)
        XCTAssertEqual(ranges.count, 1)

        let innerIndex = ranges[0].location + 1
        storage.beginEditing()
        storage.replaceCharacters(in: NSRange(location: innerIndex, length: 1), with: "x")
        storage.endEditing()

        XCTAssertEqual(storage.string, "- [x] one")
    }

    func testToggleReplacesXWithSpace() {
        let storage = NSTextStorage(string: "- [x] one")
        let highlighter = MarkdownHighlighter()
        let ranges = highlighter.taskCheckboxRanges(in: storage)
        XCTAssertEqual(ranges.count, 1)

        let innerIndex = ranges[0].location + 1
        storage.beginEditing()
        storage.replaceCharacters(in: NSRange(location: innerIndex, length: 1), with: " ")
        storage.endEditing()

        XCTAssertEqual(storage.string, "- [ ] one")
    }

    func testRangesPickUpMultipleBoxesInSeparateLines() {
        let storage = NSTextStorage(string: "- [ ] one\n- [x] two\n  - [ ] three")
        let highlighter = MarkdownHighlighter()
        let ranges = highlighter.taskCheckboxRanges(in: storage)
        XCTAssertEqual(ranges.count, 3)
    }
}
