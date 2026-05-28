import XCTest
import AppKit
@testable import MacMD

@MainActor
final class MarkdownHighlighterTests: XCTestCase {

    // MARK: - Helpers

    private func highlight(_ text: String) -> NSTextStorage {
        let storage = NSTextStorage(string: text)
        let highlighter = MarkdownHighlighter()
        storage.delegate = highlighter
        highlighter.rehighlightAll(storage)
        return storage
    }

    private func font(at location: Int, in storage: NSTextStorage) -> NSFont? {
        storage.attribute(.font, at: location, effectiveRange: nil) as? NSFont
    }

    private func color(at location: Int, in storage: NSTextStorage) -> NSColor? {
        storage.attribute(.foregroundColor, at: location, effectiveRange: nil) as? NSColor
    }

    // MARK: - Headings

    func testHeadingIsBold() {
        let storage = highlight("# Hello\nBody text")
        XCTAssertTrue(font(at: 0, in: storage)?.fontDescriptor.symbolicTraits.contains(.bold) ?? false)
        XCTAssertEqual(color(at: 0, in: storage), Theme.accentColor)
        let bodyIndex = "# Hello\n".count
        XCTAssertFalse(font(at: bodyIndex, in: storage)?.fontDescriptor.symbolicTraits.contains(.bold) ?? true)
    }

    func testSixLevelHeadings() {
        for level in 1...6 {
            let prefix = String(repeating: "#", count: level)
            let storage = highlight("\(prefix) Title")
            XCTAssertTrue(font(at: 0, in: storage)?.fontDescriptor.symbolicTraits.contains(.bold) ?? false,
                          "Level \(level) heading should be bold")
        }
    }

    // MARK: - Emphasis

    func testBoldDoubleStar() {
        let storage = highlight("This is **bold** text")
        let boldIndex = "This is **".count
        XCTAssertTrue(font(at: boldIndex, in: storage)?.fontDescriptor.symbolicTraits.contains(.bold) ?? false)
    }

    func testItalicSingleStar() {
        let storage = highlight("An *italic* word")
        let italicIndex = "An *".count
        XCTAssertTrue(font(at: italicIndex, in: storage)?.fontDescriptor.symbolicTraits.contains(.italic) ?? false)
    }

    func testStrikethroughAppliesUnderlineStyle() {
        let storage = highlight("This is ~~struck~~ text")
        let struckIndex = "This is ~~".count
        let raw = storage.attribute(.strikethroughStyle, at: struckIndex, effectiveRange: nil) as? Int
        XCTAssertEqual(raw, NSUnderlineStyle.single.rawValue)
    }

    func testStrikethroughRejectsSpaceAfterOpeningDelimiter() {
        let storage = highlight("not strike: ~~ foo ~~")
        let index = "not strike: ".count + 3
        XCTAssertNil(storage.attribute(.strikethroughStyle, at: index, effectiveRange: nil))
    }

    // MARK: - Code spans and fences

    func testInlineCodeHasBackground() {
        let storage = highlight("Use `code` here")
        let codeIndex = "Use `".count
        let bg = storage.attribute(.backgroundColor, at: codeIndex, effectiveRange: nil) as? NSColor
        XCTAssertNotNil(bg)
    }

    func testFencedCodeBlock() {
        let text = """
        Before
        ```
        let x = 1
        ```
        After
        """
        let storage = highlight(text)
        let insideIndex = (text as NSString).range(of: "let x").location
        XCTAssertEqual(color(at: insideIndex, in: storage), Theme.mutedColor)
    }

    func testUnclosedFenceStylesToEndOfDocument() {
        let text = """
        Before
        ```
        still typing
        """
        let storage = highlight(text)
        let insideIndex = (text as NSString).range(of: "still").location
        XCTAssertEqual(color(at: insideIndex, in: storage), Theme.mutedColor)
    }

    func testTildeFencedCodeBlock() {
        let text = """
        Before
        ~~~
        let x = 1
        ~~~
        After
        """
        let storage = highlight(text)
        let insideIndex = (text as NSString).range(of: "let x").location
        XCTAssertEqual(color(at: insideIndex, in: storage), Theme.mutedColor)
        let afterIndex = (text as NSString).range(of: "After").location
        XCTAssertEqual(color(at: afterIndex, in: storage), Theme.textColor)
    }

    func testBacktickFenceCannotBeClosedByTildeFence() {
        let text = """
        ```
        code one
        ~~~
        code two
        ```
        outside
        """
        let storage = highlight(text)
        let codeTwoIndex = (text as NSString).range(of: "code two").location
        XCTAssertEqual(color(at: codeTwoIndex, in: storage), Theme.mutedColor,
                       "tilde line in the middle of a backtick fence is content, not a closer")
        let outsideIndex = (text as NSString).range(of: "outside").location
        XCTAssertEqual(color(at: outsideIndex, in: storage), Theme.textColor,
                       "the second triple-backtick closes the fence")
    }

    // MARK: - Links

    func testLinkUnderlinesLabel() {
        let storage = highlight("See [Apple](https://apple.com) today")
        let labelIndex = "See [".count
        let underline = storage.attribute(.underlineStyle, at: labelIndex, effectiveRange: nil) as? Int
        XCTAssertEqual(underline, NSUnderlineStyle.single.rawValue)
        XCTAssertEqual(color(at: labelIndex, in: storage), Theme.linkColor)
    }

    // MARK: - Lists

    func testUnorderedListMarker() {
        let storage = highlight("- First item")
        XCTAssertEqual(color(at: 0, in: storage), Theme.accentColor)
    }

    func testOrderedListMarker() {
        let storage = highlight("1. First item")
        XCTAssertEqual(color(at: 0, in: storage), Theme.accentColor)
    }

    func testOrderedListMarkerWithParen() {
        let storage = highlight("1) First item")
        XCTAssertEqual(color(at: 0, in: storage), Theme.accentColor)
    }

    func testAsteriskListMarkerIsNotItalicized() {
        let storage = highlight("* item one")
        let contentIndex = "* ".count
        XCTAssertFalse(font(at: contentIndex, in: storage)?.fontDescriptor.symbolicTraits.contains(.italic) ?? true,
                       "Bullet list item with asterisk must not trigger italic")
        XCTAssertEqual(color(at: 0, in: storage), Theme.accentColor,
                       "Asterisk list marker should be accent-colored")
    }

    // MARK: - Blockquotes, rules, plain text

    func testBlockquote() {
        let storage = highlight("> quoted text")
        XCTAssertEqual(color(at: 0, in: storage), Theme.mutedColor)
        XCTAssertTrue(font(at: 0, in: storage)?.fontDescriptor.symbolicTraits.contains(.italic) ?? false)
    }

    func testHorizontalRule() {
        let storage = highlight("---")
        XCTAssertEqual(color(at: 0, in: storage), Theme.mutedColor)
    }

    func testPlainTextFallsBack() {
        let storage = highlight("just some plain text")
        XCTAssertEqual(color(at: 0, in: storage), Theme.textColor)
    }

    // MARK: - Composition

    func testItalicRejectsSpaceAfterOpeningDelimiter() {
        let storage = highlight("not italic: * foo *")
        let index = "not italic: ".count + 2
        XCTAssertFalse(font(at: index, in: storage)?.fontDescriptor.symbolicTraits.contains(.italic) ?? true)
    }

    func testBoldRejectsSpaceAfterOpeningDelimiter() {
        let storage = highlight("not bold: ** foo **")
        let index = "not bold: ".count + 3
        XCTAssertFalse(font(at: index, in: storage)?.fontDescriptor.symbolicTraits.contains(.bold) ?? true)
    }

    func testBoldItalicCompose() {
        let text = "**outer *inner* outer**"
        let storage = highlight(text)
        let innerIndex = (text as NSString).range(of: "inner").location
        let innerFont = font(at: innerIndex, in: storage)
        let traits = innerFont?.fontDescriptor.symbolicTraits ?? []
        XCTAssertTrue(traits.contains(.bold), "Inner should retain bold from outer")
        XCTAssertTrue(traits.contains(.italic), "Inner should also be italic")

        let outerIndex = (text as NSString).range(of: "outer ").location
        let outerTraits = font(at: outerIndex, in: storage)?.fontDescriptor.symbolicTraits ?? []
        XCTAssertTrue(outerTraits.contains(.bold), "Outer must remain bold")
        XCTAssertFalse(outerTraits.contains(.italic), "Outer must NOT be italic")
    }

    func testBlockquoteComposesWithBold() {
        let text = "> **bolded** in a quote"
        let storage = highlight(text)
        let boldedIndex = (text as NSString).range(of: "bolded").location
        let traits = font(at: boldedIndex, in: storage)?.fontDescriptor.symbolicTraits ?? []
        XCTAssertTrue(traits.contains(.bold), "Bold inside blockquote must remain bold")
        XCTAssertTrue(traits.contains(.italic), "Blockquote still adds italic trait")
    }

    // MARK: - Paragraph styling and partial edits

    func testBodyParagraphStyleApplied() {
        let storage = highlight("Line one.")
        let paragraphStyle = storage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertEqual(paragraphStyle?.lineSpacing, Theme.editorLineSpacing)
    }

    func testPartialEditRehighlights() {
        let storage = NSTextStorage(string: "plain line\nanother line")
        let highlighter = MarkdownHighlighter()
        storage.delegate = highlighter
        highlighter.rehighlightAll(storage)
        storage.beginEditing()
        storage.replaceCharacters(in: NSRange(location: 0, length: 5), with: "# Big")
        storage.endEditing()
        XCTAssertTrue(font(at: 0, in: storage)?.fontDescriptor.symbolicTraits.contains(.bold) ?? false)
    }

    // MARK: - Fence boundary rehighlight

    func testAddingFenceRehighlightsFollowingContent() {
        let storage = NSTextStorage(string: "hello world\nmore text\n")
        let highlighter = MarkdownHighlighter()
        storage.delegate = highlighter
        highlighter.rehighlightAll(storage)

        let moreIndexBefore = (storage.string as NSString).range(of: "more").location
        XCTAssertEqual(color(at: moreIndexBefore, in: storage), Theme.textColor,
                       "Content should start as plain text before any fence is added")

        storage.beginEditing()
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "```\n")
        storage.endEditing()

        let moreIndexAfter = (storage.string as NSString).range(of: "more").location
        XCTAssertEqual(color(at: moreIndexAfter, in: storage), Theme.mutedColor,
                       "Content below a newly-added unclosed fence must re-highlight as code")
    }

    func testRemovingFenceRehighlightsReleasedContent() {
        let storage = NSTextStorage(string: "```\ncode here\n```\nafter\n")
        let highlighter = MarkdownHighlighter()
        storage.delegate = highlighter
        highlighter.rehighlightAll(storage)

        let codeIndexBefore = (storage.string as NSString).range(of: "code").location
        XCTAssertEqual(color(at: codeIndexBefore, in: storage), Theme.mutedColor,
                       "Content inside a fence should start muted")

        storage.beginEditing()
        storage.replaceCharacters(in: NSRange(location: 0, length: 4), with: "")
        storage.endEditing()

        let codeIndexAfter = (storage.string as NSString).range(of: "code").location
        XCTAssertEqual(color(at: codeIndexAfter, in: storage), Theme.textColor,
                       "Content should return to plain text after its opening fence is deleted")
    }

    // MARK: - Disabled mode

    func testDisabledHighlighterAppliesNoAttributes() {
        let storage = NSTextStorage(string: "# Heading\nBody")
        let highlighter = MarkdownHighlighter()
        storage.delegate = highlighter
        highlighter.isDisabled = true
        highlighter.rehighlightAll(storage)
        XCTAssertNil(storage.attribute(.foregroundColor, at: 0, effectiveRange: nil))
        XCTAssertNil(storage.attribute(.paragraphStyle, at: 0, effectiveRange: nil))
    }

    func testDisabledHighlighterIgnoresEdits() {
        let storage = NSTextStorage(string: "plain")
        let highlighter = MarkdownHighlighter()
        storage.delegate = highlighter
        highlighter.rehighlightAll(storage)
        highlighter.isDisabled = true
        storage.beginEditing()
        storage.replaceCharacters(in: NSRange(location: 0, length: 5), with: "# Big")
        storage.endEditing()
        let f = storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        let traits = f?.fontDescriptor.symbolicTraits ?? []
        XCTAssertFalse(traits.contains(.bold), "disabled highlighter must not apply heading bold")
    }

    // MARK: - Task lists

    func testUnfinishedTaskListBracketIsAccent() {
        let storage = highlight("- [ ] buy milk")
        let bracketIndex = "- ".count
        XCTAssertEqual(color(at: bracketIndex, in: storage), Theme.accentColor)
    }

    func testFinishedTaskListBracketIsAccentAndBodyIsStruck() {
        let text = "- [x] mow lawn"
        let storage = highlight(text)
        let bracketIndex = "- ".count
        XCTAssertEqual(color(at: bracketIndex, in: storage), Theme.accentColor)
        let bodyIndex = (text as NSString).range(of: "mow").location
        let raw = storage.attribute(.strikethroughStyle, at: bodyIndex, effectiveRange: nil) as? Int
        XCTAssertEqual(raw, NSUnderlineStyle.single.rawValue)
    }

    func testUnfinishedTaskListBodyIsNotStruck() {
        let text = "- [ ] buy milk"
        let storage = highlight(text)
        let bodyIndex = (text as NSString).range(of: "buy").location
        XCTAssertNil(storage.attribute(.strikethroughStyle, at: bodyIndex, effectiveRange: nil))
    }

    // MARK: - Task checkbox ranges

    func testTaskCheckboxRangesEmptyWhenNoTaskLists() {
        let storage = NSTextStorage(string: "# Heading\nBody")
        let highlighter = MarkdownHighlighter()
        XCTAssertEqual(highlighter.taskCheckboxRanges(in: storage), [])
    }

    func testTaskCheckboxRangesFindsBracketPairs() {
        let text = "- [ ] one\n- [x] two\n"
        let storage = NSTextStorage(string: text)
        let highlighter = MarkdownHighlighter()
        let ranges = highlighter.taskCheckboxRanges(in: storage)
        XCTAssertEqual(ranges.count, 2)
        XCTAssertEqual((text as NSString).substring(with: ranges[0]), "[ ]")
        XCTAssertEqual((text as NSString).substring(with: ranges[1]), "[x]")
    }

    func testTaskCheckboxRangesEmptyWhenDisabled() {
        let storage = NSTextStorage(string: "- [ ] one")
        let highlighter = MarkdownHighlighter()
        highlighter.isDisabled = true
        XCTAssertEqual(highlighter.taskCheckboxRanges(in: storage), [])
    }
}
