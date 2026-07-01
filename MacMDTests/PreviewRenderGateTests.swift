import XCTest
@testable import MacMD

final class PreviewRenderGateTests: XCTestCase {

    func testLiveRenderDisabledAtSoftLimit() {
        XCTAssertTrue(PreviewWebView.allowsLiveRender(byteCount: MarkdownDocument.softSizeLimit - 1))
        XCTAssertFalse(PreviewWebView.allowsLiveRender(byteCount: MarkdownDocument.softSizeLimit))
    }

    func testScrollInvocationBuildsScrollToLineCall() {
        XCTAssertEqual(PreviewWebView.scrollInvocation(line: 42), "scrollToLine(42)")
    }
}
