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
}
