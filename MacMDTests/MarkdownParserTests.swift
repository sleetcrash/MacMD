import XCTest
@testable import MacMD

final class MarkdownParserTests: XCTestCase {

    // MARK: - Fenced code

    func testFenceSpansMatchesHighlighterFenceLogic() {
        // A closed backtick fence, a closed tilde fence, and an unclosed trailing
        // fence. The unclosed fence runs to end-of-document, matching the behavior
        // the highlighter's testUnclosedFenceStylesToEndOfDocument and
        // testBacktickFenceCannotBeClosedByTildeFence already pin. A fence span
        // starts at its opening line and ends at the closing line's last non-newline
        // character (the trailing newline is excluded), exactly as spansFromFences
        // computed it inside MarkdownRules.
        let text = "```\nalpha\n```\n~~~\nbeta\n~~~\n```\ngamma\n"
        let expected = [
            NSRange(location: 0, length: 13),   // ``` alpha ``` (closing newline excluded)
            NSRange(location: 14, length: 12),  // ~~~ beta ~~~
            NSRange(location: 27, length: 10),  // ``` gamma ... unclosed, runs to end of document
        ]
        XCTAssertEqual(MarkdownParser.fenceSpans(in: text), expected)
    }

    // MARK: - Headings

    func testHeadingsCoverAtxAndSetextExcludingFences() {
        // "# One"  -> ATX H1
        // "Two\n===" -> setext H1
        // fenced "# not a heading" -> excluded
        // "Three\n---" -> setext H2
        let text = "# One\nbody\nTwo\n===\n```\n# not a heading\n```\nThree\n---\n"
        let headings = MarkdownParser.headings(in: text)

        XCTAssertEqual(headings.map(\.title), ["One", "Two", "Three"])
        XCTAssertEqual(headings.map(\.level), [1, 1, 2])

        // Each lineRange is the heading TEXT line (excluding the trailing newline):
        // the ATX line for "# One", and the title line (not the underline) for setext.
        XCTAssertEqual(headings[0].lineRange, NSRange(location: 0, length: 5))   // "# One"
        XCTAssertEqual(headings[1].lineRange, NSRange(location: 11, length: 3))  // "Two"
        XCTAssertEqual(headings[2].lineRange, NSRange(location: 43, length: 5))  // "Three"

        // The fenced "# not a heading" is not returned.
        XCTAssertFalse(headings.contains { $0.title.contains("not a heading") })
    }
}
