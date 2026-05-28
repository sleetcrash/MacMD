import XCTest
@testable import MacMD

final class MarkdownDocumentTests: XCTestCase {
    func testDecodeReturnsStringForValidUTF8() throws {
        let data = Data("# Heading".utf8)
        XCTAssertEqual(try MarkdownDocument.decode(data), "# Heading")
    }

    func testDecodeStripsLeadingUTF8BOM() throws {
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(Data("# Heading".utf8))
        XCTAssertEqual(try MarkdownDocument.decode(data), "# Heading")
    }

    func testDecodeDoesNotStripBOMMidString() throws {
        let s = "ok\u{FEFF}still here"
        let data = Data(s.utf8)
        XCTAssertEqual(try MarkdownDocument.decode(data), s)
    }

    func testEncodeAppendsTrailingNewlineWhenMissing() {
        let data = MarkdownDocument.encode("hello")
        XCTAssertEqual(String(data: data, encoding: .utf8), "hello\n")
    }

    func testEncodeDoesNotDoubleTrailingNewline() {
        let data = MarkdownDocument.encode("hello\n")
        XCTAssertEqual(String(data: data, encoding: .utf8), "hello\n")
    }

    func testEncodeLeavesEmptyTextEmpty() {
        let data = MarkdownDocument.encode("")
        XCTAssertEqual(String(data: data, encoding: .utf8), "")
    }
}
