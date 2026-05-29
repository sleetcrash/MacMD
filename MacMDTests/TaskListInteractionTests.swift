import XCTest
import AppKit
@testable import MacMD

@MainActor
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

    func testFormatCommandTogglesCheckboxOnCaretLine() {
        let textView = ClickableTextView()
        let highlighter = MarkdownHighlighter()
        textView.highlighter = highlighter
        textView.string = "- [ ] one\n- [ ] two"
        let caret = (textView.string as NSString).range(of: "two").location
        textView.setSelectedRange(NSRange(location: caret, length: 0))

        textView.toggleTaskCheckbox(nil)

        XCTAssertEqual(textView.string, "- [ ] one\n- [x] two",
                       "Only the checkbox on the caret's line should flip")
    }

    func testFormatCommandTogglesCheckedBackToUnchecked() {
        let textView = ClickableTextView()
        let highlighter = MarkdownHighlighter()
        textView.highlighter = highlighter
        textView.string = "- [x] done"
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        textView.toggleTaskCheckbox(nil)

        XCTAssertEqual(textView.string, "- [ ] done")
    }

    func testFormatCommandIsNoOpWhenCaretLineHasNoCheckbox() {
        let textView = ClickableTextView()
        let highlighter = MarkdownHighlighter()
        textView.highlighter = highlighter
        textView.string = "plain paragraph"
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        textView.toggleTaskCheckbox(nil)

        XCTAssertEqual(textView.string, "plain paragraph")
    }
}
