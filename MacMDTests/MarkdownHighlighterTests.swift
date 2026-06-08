import XCTest
import AppKit
@testable import MacMD

@MainActor
final class MarkdownHighlighterTests: XCTestCase {

    override func tearDown() {
        Theme.setActiveTheme(coloring: .off, palette: ColorTheming.standardPresets[0])
        super.tearDown()
    }

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
        XCTAssertEqual(color(at: 0, in: storage), Theme.textColor)
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
        XCTAssertEqual(color(at: 0, in: storage), Theme.textColor)
    }

    func testOrderedListMarker() {
        let storage = highlight("1. First item")
        XCTAssertEqual(color(at: 0, in: storage), Theme.textColor)
    }

    func testOrderedListMarkerWithParen() {
        let storage = highlight("1) First item")
        XCTAssertEqual(color(at: 0, in: storage), Theme.textColor)
    }

    func testAsteriskListMarkerIsNotItalicized() {
        let storage = highlight("* item one")
        let contentIndex = "* ".count
        XCTAssertFalse(font(at: contentIndex, in: storage)?.fontDescriptor.symbolicTraits.contains(.italic) ?? true,
                       "Bullet list item with asterisk must not trigger italic")
        XCTAssertEqual(color(at: 0, in: storage), Theme.textColor,
                       "Asterisk list marker should use the body label color (Default scheme)")
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

    // MARK: - Editor font size

    func testEditorFontSizeClampsBelowMinimum() {
        Theme.setEditorFontSize(4)
        XCTAssertEqual(Theme.editorFontSize, FontSize.minimum)
        XCTAssertEqual(Theme.editorFont.pointSize, FontSize.minimum)
        Theme.setEditorFontSize(FontSize.standard)
    }

    func testEditorFontSizeClampsAboveMaximum() {
        Theme.setEditorFontSize(500)
        XCTAssertEqual(Theme.editorFontSize, FontSize.maximum)
        Theme.setEditorFontSize(FontSize.standard)
    }

    func testEditorFontSizeRebuildsHeadingFonts() {
        Theme.setEditorFontSize(20)
        XCTAssertEqual(Theme.editorFont.pointSize, 20)
        XCTAssertEqual(Theme.headingFont(level: 6).pointSize, 21, "level 6 bumps the base by one point")
        XCTAssertEqual(Theme.headingFont(level: 1).pointSize, 26, "level 1 bumps the base by six points")
        Theme.setEditorFontSize(FontSize.standard)
    }

    func testEditorFontSizeChangeReportsWhetherItChanged() {
        Theme.setEditorFontSize(FontSize.standard)
        XCTAssertFalse(Theme.setEditorFontSize(FontSize.standard), "no change should report false")
        XCTAssertTrue(Theme.setEditorFontSize(FontSize.standard + 2), "a real change should report true")
        Theme.setEditorFontSize(FontSize.standard)
    }

    func testLongEmphasisLineHighlightsWithoutBacktracking() {
        // A single long line of "** a ** a ..." used to send the bold rules into
        // catastrophic backtracking and peg the main thread for minutes. The inner
        // run is now bounded so this must finish near-instantly.
        let line = "a " + String(repeating: "** a ", count: 40_000)
        let storage = NSTextStorage(string: line)
        let highlighter = MarkdownHighlighter()
        storage.delegate = highlighter
        let started = CFAbsoluteTimeGetCurrent()
        highlighter.rehighlightAll(storage)
        XCTAssertLessThan(CFAbsoluteTimeGetCurrent() - started, 2.0,
                          "Emphasis highlighting must stay linear on long lines")
    }

    func testLongLinkLineHighlightsWithoutBacktracking() {
        // A single long line of "[a](" repeated (no closing paren) used to send the
        // link rule into catastrophic O(n^2) backtracking and peg the main thread
        // for minutes. The inner runs are now atomic and bounded so this must
        // finish near-instantly.
        let line = String(repeating: "[a](", count: 40_000)
        let storage = NSTextStorage(string: line)
        let highlighter = MarkdownHighlighter()
        storage.delegate = highlighter
        let started = CFAbsoluteTimeGetCurrent()
        highlighter.rehighlightAll(storage)
        XCTAssertLessThan(CFAbsoluteTimeGetCurrent() - started, 2.0,
                          "Link highlighting must stay linear on long lines")
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
        XCTAssertEqual(color(at: bracketIndex, in: storage), Theme.textColor)
    }

    func testFinishedTaskListBracketIsAccentAndBodyIsStruck() {
        let text = "- [x] mow lawn"
        let storage = highlight(text)
        let bracketIndex = "- ".count
        XCTAssertEqual(color(at: bracketIndex, in: storage), Theme.textColor)
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

    // MARK: - Section-color theming

    private func headingColorTest(_ text: String, coloring: Coloring, paletteId: String) -> NSTextStorage {
        Theme.setActiveTheme(coloring: coloring, palette: ColorTheming.preset(id: paletteId))
        return highlight(text)
    }

    func testStandardSchemeColorsHeadingsBySlot() {
        let storage = headingColorTest("# H1\n## H2\n### H3", coloring: .standard, paletteId: "std.rgb")
        XCTAssertEqual(color(at: 0, in: storage)?.resolvedHexLight, "#C13F50")            // H1
        let h2 = ("# H1\n").count
        XCTAssertEqual(color(at: h2, in: storage)?.resolvedHexLight, "#2E8049")           // H2
        let h3 = ("# H1\n## H2\n").count
        XCTAssertEqual(color(at: h3, in: storage)?.resolvedHexLight, "#2E86AB")           // H3
    }

    func testUnifiedSchemeColorsAllHeadingsSame() {
        let storage = headingColorTest("# H1\n## H2", coloring: .unified, paletteId: "uni.teal")
        XCTAssertEqual(color(at: 0, in: storage)?.resolvedHexLight, "#2E86AB")
        let h2 = ("# H1\n").count
        XCTAssertEqual(color(at: h2, in: storage)?.resolvedHexLight, "#2E86AB")
    }

    func testMarkerInheritsGoverningHeadingColor() {
        // Bullet under ## Section takes the H2 (slot1) color.
        let text = "## Section\n- item"
        let storage = headingColorTest(text, coloring: .standard, paletteId: "std.rgb")
        let bulletIndex = ("## Section\n").count   // the "-" of "- item"
        XCTAssertEqual(color(at: bulletIndex, in: storage)?.resolvedHexLight, "#2E8049")
    }

    func testMarkerBeforeAnyHeadingTakesH1Color() {
        let text = "- loose\n# Heading"
        let storage = headingColorTest(text, coloring: .standard, paletteId: "std.rgb")
        XCTAssertEqual(color(at: 0, in: storage)?.resolvedHexLight, "#C13F50")  // H1 color
    }

    func testDefaultSchemeKeepsMarkersLabelColor() {
        Theme.setActiveTheme(coloring: .off, palette: ColorTheming.standardPresets[0])
        let storage = highlight("## Section\n- item")
        let bulletIndex = ("## Section\n").count
        XCTAssertEqual(color(at: bulletIndex, in: storage), Theme.textColor)
    }

    func testEditingAHeadingRecolorsMarkersBelow() {
        Theme.setActiveTheme(coloring: .standard, palette: ColorTheming.preset(id: "std.rgb"))
        let storage = NSTextStorage(string: "## Section\n- item")
        let highlighter = MarkdownHighlighter()
        storage.delegate = highlighter
        highlighter.rehighlightAll(storage)

        let bulletIndex = ("## Section\n").count
        XCTAssertEqual(color(at: bulletIndex, in: storage)?.resolvedHexLight, "#2E8049") // H2 slot1

        // Promote the heading to H1 by deleting one '#'. The bullet must recolor
        // to the H1 (slot0) color even though only the heading line was edited.
        storage.beginEditing()
        storage.replaceCharacters(in: NSRange(location: 0, length: 1), with: "")
        storage.endEditing()

        let newBulletIndex = ("# Section\n").count
        XCTAssertEqual(color(at: newBulletIndex, in: storage)?.resolvedHexLight, "#C13F50") // H1 slot0
    }

    // MARK: - Front matter

    func testYamlFrontMatterBodyIsMuted() {
        let text = "---\ntitle: Hello\n---\nBody\n"
        let storage = highlight(text)
        let titleIndex = (text as NSString).range(of: "title").location
        XCTAssertEqual(color(at: titleIndex, in: storage), Theme.mutedColor)
        let bodyIndex = (text as NSString).range(of: "Body").location
        XCTAssertEqual(color(at: bodyIndex, in: storage), Theme.textColor)
    }

    func testTomlFrontMatterBodyIsMuted() {
        let text = "+++\ntitle = \"Hello\"\n+++\nBody\n"
        let storage = highlight(text)
        let titleIndex = (text as NSString).range(of: "title").location
        XCTAssertEqual(color(at: titleIndex, in: storage), Theme.mutedColor)
        let bodyIndex = (text as NSString).range(of: "Body").location
        XCTAssertEqual(color(at: bodyIndex, in: storage), Theme.textColor)
    }

    func testFrontMatterWithoutClosingIsNotMuted() {
        let text = "---\ntitle: Hello\nBody\n"
        let storage = highlight(text)
        let titleIndex = (text as NSString).range(of: "title").location
        XCTAssertEqual(color(at: titleIndex, in: storage), Theme.textColor)
    }

    func testDelimiterNotAtHeadIsNotFrontMatter() {
        let text = "Intro\n---\ntitle: Hello\n---\n"
        let storage = highlight(text)
        let titleIndex = (text as NSString).range(of: "title").location
        XCTAssertEqual(color(at: titleIndex, in: storage), Theme.textColor)
    }

    // An empty front-matter block (--- immediately followed by ---) must not
    // bleed its muting into the body below it. (The delimiter lines are muted by
    // the existing horizontal-rule rule regardless, so this guards the body only.)
    func testEmptyFrontMatterDelimitersDoNotMuteBody() {
        let text = "---\n---\nBody\n"
        let storage = highlight(text)
        let bodyIndex = (text as NSString).range(of: "Body").location
        XCTAssertEqual(color(at: bodyIndex, in: storage), Theme.textColor)
    }

    func testCompletingFrontMatterRehighlights() {
        let storage = NSTextStorage(string: "---\ntitle: Hello\nBody\n")
        let highlighter = MarkdownHighlighter()
        storage.delegate = highlighter
        highlighter.rehighlightAll(storage)
        let titleBefore = (storage.string as NSString).range(of: "title").location
        XCTAssertEqual(color(at: titleBefore, in: storage), Theme.textColor,
                       "No closing delimiter yet, so not front matter")
        let bodyLoc = (storage.string as NSString).range(of: "Body").location
        storage.beginEditing()
        storage.replaceCharacters(in: NSRange(location: bodyLoc, length: 0), with: "---\n")
        storage.endEditing()
        let titleAfter = (storage.string as NSString).range(of: "title").location
        XCTAssertEqual(color(at: titleAfter, in: storage), Theme.mutedColor,
                       "Closing the block must re-highlight the body as muted front matter")
    }

    func testInlineRulesAreSuppressedInsideFrontMatter() {
        let text = "---\n[link](url)\n---\nBody\n"
        let storage = highlight(text)
        let linkIndex = (text as NSString).range(of: "link").location
        XCTAssertEqual(color(at: linkIndex, in: storage), Theme.mutedColor,
                       "Inline rules must not style content inside a front-matter block")
    }

    func testFrontMatterClosingOnLastLineWithoutNewline() {
        let text = "---\ntitle: Hello\n---"
        let storage = highlight(text)
        let titleIndex = (text as NSString).range(of: "title").location
        XCTAssertEqual(color(at: titleIndex, in: storage), Theme.mutedColor)
    }

    // MARK: - clearHighlighting (Plain mode)

    func testClearHighlightingRestoresBaseAttributes() {
        Theme.setActiveTheme(coloring: .standard, palette: ColorTheming.standardPresets[0])
        let storage = NSTextStorage(string: "# Heading\nbody **bold** `code`")
        let highlighter = MarkdownHighlighter()
        storage.delegate = highlighter
        highlighter.rehighlightAll(storage)
        XCTAssertTrue((font(at: 0, in: storage))?.fontDescriptor.symbolicTraits.contains(.bold) ?? false)

        highlighter.clearHighlighting(storage)

        let full = NSRange(location: 0, length: storage.length)
        storage.enumerateAttribute(.font, in: full, options: []) { value, _, _ in
            XCTAssertEqual(value as? NSFont, Theme.editorFont)
        }
        XCTAssertEqual(color(at: 0, in: storage), Theme.textColor)
        XCTAssertNil(storage.attribute(.underlineStyle, at: 0, effectiveRange: nil))
        XCTAssertNil(storage.attribute(.strikethroughStyle, at: 0, effectiveRange: nil))
        XCTAssertNil(storage.attribute(.backgroundColor, at: 0, effectiveRange: nil))
    }

    // MARK: - Code font stays monospace under a proportional body font

    func testInlineCodeUsesMonospaceFontUnderProportionalBody() {
        Theme.setEditorFontFamily(FontFamily.resolve(id: "georgia"))
        defer { Theme.setEditorFontFamily(.default) }
        let storage = highlight("Body `code` here")
        let codeIndex = "Body `".count
        XCTAssertTrue((font(at: codeIndex, in: storage))?.isFixedPitch ?? false)
        XCTAssertFalse((font(at: 0, in: storage))?.isFixedPitch ?? true)
    }

    func testFencedCodeUsesMonospaceFontUnderProportionalBody() {
        Theme.setEditorFontFamily(FontFamily.resolve(id: "georgia"))
        defer { Theme.setEditorFontFamily(.default) }
        let storage = highlight("```\nlet x = 1\n```")
        let insideIndex = "```\nlet".count
        XCTAssertTrue((font(at: insideIndex, in: storage))?.isFixedPitch ?? false)
    }
}
