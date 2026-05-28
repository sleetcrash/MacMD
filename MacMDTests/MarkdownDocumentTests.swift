import XCTest
@testable import MacMD

final class MarkdownDocumentTests: XCTestCase {
    func testDecodeReturnsStringForValidUTF8() throws {
        let data = Data("# Heading".utf8)
        XCTAssertEqual(try MarkdownDocument.decode(data), "# Heading")
    }
}
