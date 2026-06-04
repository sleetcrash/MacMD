import XCTest
@testable import MacMD

final class EditingCommandsTests: XCTestCase {

    // MARK: - Emphasis toggle: wrap

    func testBoldWrapsNonEmptySelection() {
        let text = "hello world" as NSString
        let selection = NSRange(location: 6, length: 5) // "world"
        let edit = EditingCommands.emphasisToggle(in: text, selection: selection, marker: "**")
        XCTAssertEqual(edit.range, selection)
        XCTAssertEqual(edit.replacement, "**world**")
        XCTAssertEqual(edit.selectionAfter, NSRange(location: 8, length: 5))
    }

    func testItalicWrapsNonEmptySelection() {
        let text = "hello world" as NSString
        let selection = NSRange(location: 0, length: 5) // "hello"
        let edit = EditingCommands.emphasisToggle(in: text, selection: selection, marker: "*")
        XCTAssertEqual(edit.range, selection)
        XCTAssertEqual(edit.replacement, "*hello*")
        XCTAssertEqual(edit.selectionAfter, NSRange(location: 1, length: 5))
    }

    // MARK: - Emphasis toggle: unwrap (marker flanks the selection)

    func testBoldUnwrapsWhenFlanked() {
        let text = "**world**" as NSString
        let selection = NSRange(location: 2, length: 5) // inner "world"
        let edit = EditingCommands.emphasisToggle(in: text, selection: selection, marker: "**")
        XCTAssertEqual(edit.range, NSRange(location: 0, length: 9))
        XCTAssertEqual(edit.replacement, "world")
        XCTAssertEqual(edit.selectionAfter, NSRange(location: 0, length: 5))
    }

    func testItalicUnwrapsWhenFlanked() {
        let text = "*hi*" as NSString
        let selection = NSRange(location: 1, length: 2) // "hi"
        let edit = EditingCommands.emphasisToggle(in: text, selection: selection, marker: "*")
        XCTAssertEqual(edit.range, NSRange(location: 0, length: 4))
        XCTAssertEqual(edit.replacement, "hi")
        XCTAssertEqual(edit.selectionAfter, NSRange(location: 0, length: 2))
    }

    // MARK: - Link wrap

    func testLinkWrapsSelectionAndSelectsURLPlaceholder() {
        let text = "see docs" as NSString
        let selection = NSRange(location: 4, length: 4) // "docs"
        let edit = EditingCommands.linkWrap(in: text, selection: selection)
        XCTAssertEqual(edit.range, selection)
        XCTAssertEqual(edit.replacement, "[docs](url)")
        XCTAssertEqual(edit.selectionAfter, NSRange(location: 11, length: 3)) // "url"
    }

    func testLinkEmptySelectionInsertsTemplateWithCaretInBrackets() {
        let text = "" as NSString
        let edit = EditingCommands.linkWrap(in: text, selection: NSRange(location: 0, length: 0))
        XCTAssertEqual(edit.replacement, "[](url)")
        XCTAssertEqual(edit.selectionAfter, NSRange(location: 1, length: 0))
    }

    // MARK: - Emphasis toggle: empty selection inserts the pair, caret between

    func testBoldEmptySelectionInsertsPairWithCaretBetween() {
        let text = "" as NSString
        let edit = EditingCommands.emphasisToggle(in: text, selection: NSRange(location: 0, length: 0), marker: "**")
        XCTAssertEqual(edit.replacement, "****")
        XCTAssertEqual(edit.selectionAfter, NSRange(location: 2, length: 0))
    }

    func testItalicEmptySelectionInsertsPairWithCaretBetween() {
        let text = "" as NSString
        let edit = EditingCommands.emphasisToggle(in: text, selection: NSRange(location: 0, length: 0), marker: "*")
        XCTAssertEqual(edit.replacement, "**")
        XCTAssertEqual(edit.selectionAfter, NSRange(location: 1, length: 0))
    }

    // MARK: - List continuation: unordered

    func testUnorderedContinuationPreservesBullet() {
        XCTAssertEqual(EditingCommands.listContinuation(forLine: "- item"), .continue(newPrefix: "- "))
        XCTAssertEqual(EditingCommands.listContinuation(forLine: "* item"), .continue(newPrefix: "* "))
        XCTAssertEqual(EditingCommands.listContinuation(forLine: "+ item"), .continue(newPrefix: "+ "))
    }

    func testUnorderedContinuationPreservesIndentation() {
        XCTAssertEqual(EditingCommands.listContinuation(forLine: "  - nested"), .continue(newPrefix: "  - "))
    }

    // MARK: - List continuation: ordered increments

    func testOrderedContinuationIncrements() {
        XCTAssertEqual(EditingCommands.listContinuation(forLine: "1. first"), .continue(newPrefix: "2. "))
        XCTAssertEqual(EditingCommands.listContinuation(forLine: "3) third"), .continue(newPrefix: "4) "))
    }

    // MARK: - List continuation: task items continue unchecked

    func testTaskContinuationStartsUnchecked() {
        XCTAssertEqual(EditingCommands.listContinuation(forLine: "- [ ] todo"), .continue(newPrefix: "- [ ] "))
        XCTAssertEqual(EditingCommands.listContinuation(forLine: "- [x] done"), .continue(newPrefix: "- [ ] "))
    }

    // MARK: - List continuation: empty item terminates the list

    func testEmptyUnorderedItemTerminates() {
        XCTAssertEqual(EditingCommands.listContinuation(forLine: "- "), .terminate(prefixLength: 2))
    }

    func testEmptyOrderedItemTerminates() {
        XCTAssertEqual(EditingCommands.listContinuation(forLine: "1. "), .terminate(prefixLength: 3))
    }

    func testEmptyTaskItemTerminates() {
        XCTAssertEqual(EditingCommands.listContinuation(forLine: "- [ ] "), .terminate(prefixLength: 6))
    }

    // MARK: - List continuation: non-list lines

    func testNonListLineReturnsNone() {
        XCTAssertEqual(EditingCommands.listContinuation(forLine: "just text"), .none)
        XCTAssertEqual(EditingCommands.listContinuation(forLine: ""), .none)
        XCTAssertEqual(EditingCommands.listContinuation(forLine: "# heading"), .none)
    }

    // MARK: - Characterization (pinned, accepted Phase 1 limitations)

    /// ⌘I on a word inside **bold** must ADD italic (wrap), not strip a bold
    /// asterisk. The flanking `*` is part of `**`, so it is not an italic
    /// marker. Result: ***word***.
    func testItalicInsideBoldAddsItalicNotStripBold() {
        let text = "**word**" as NSString
        let selection = NSRange(location: 2, length: 4) // "word"
        let edit = EditingCommands.emphasisToggle(in: text, selection: selection, marker: "*")
        XCTAssertEqual(edit.range, selection)
        XCTAssertEqual(edit.replacement, "*word*")
        XCTAssertEqual(edit.selectionAfter, NSRange(location: 3, length: 4))
    }

    /// Bold toggle-off of **word** still works: the flanking `**` is the exact
    /// marker, not extended by a further `*`.
    func testBoldToggleOffStillUnwraps() {
        let text = "**word**" as NSString
        let selection = NSRange(location: 2, length: 4)
        let edit = EditingCommands.emphasisToggle(in: text, selection: selection, marker: "**")
        XCTAssertEqual(edit.range, NSRange(location: 0, length: 8))
        XCTAssertEqual(edit.replacement, "word")
    }

    /// Italic toggle-off of a lone *word* still works.
    func testItalicToggleOffLoneMarkers() {
        let text = "*word*" as NSString
        let selection = NSRange(location: 1, length: 4)
        let edit = EditingCommands.emphasisToggle(in: text, selection: selection, marker: "*")
        XCTAssertEqual(edit.range, NSRange(location: 0, length: 6))
        XCTAssertEqual(edit.replacement, "word")
    }

    /// Known edge (pinned): italicizing a word inside ***bold+italic*** wraps
    /// rather than removing the italic layer. Full asterisk-run parsing is out
    /// of scope for this minimal editor; pinned so the behavior stays deliberate.
    func testTripleAsteriskItalicWraps() {
        let text = "***word***" as NSString
        let selection = NSRange(location: 3, length: 4)
        let edit = EditingCommands.emphasisToggle(in: text, selection: selection, marker: "*")
        XCTAssertEqual(edit.range, selection)
        XCTAssertEqual(edit.replacement, "*word*")
    }

    func testIndentedEmptyItemTerminates() {
        XCTAssertEqual(EditingCommands.listContinuation(forLine: "  - "), .terminate(prefixLength: 4))
    }
}
