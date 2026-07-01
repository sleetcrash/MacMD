import XCTest
@testable import MacMD

final class MarkdownRenderEngineTests: XCTestCase {

    // MARK: - Nonce

    func testMakeNonceIsUnique128BitBase64() {
        let a = MarkdownRenderEngine.makeNonce()
        let b = MarkdownRenderEngine.makeNonce()
        XCTAssertNotEqual(a, b, "each render must get a fresh nonce")
        for nonce in [a, b] {
            let decoded = Data(base64Encoded: nonce)
            XCTAssertNotNil(decoded, "nonce must be valid base64")
            XCTAssertEqual(decoded?.count, 16, "nonce must be 128 bits")
        }
    }
}
