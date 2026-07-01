import XCTest
import WebKit
@testable import MacMD

final class PreviewNavigationTests: XCTestCase {

    func testInitialMacmdLoadAllowed() {
        let url = URL(string: "macmd-resource://app/index.html")
        XCTAssertEqual(PreviewNavigation.decision(isInitialLoad: true, navigationType: .other, url: url), .allow)
    }

    func testSubsequentNavigationIsCancelled() {
        let url = URL(string: "macmd-resource://app/index.html")
        XCTAssertEqual(PreviewNavigation.decision(isInitialLoad: false, navigationType: .other, url: url), .cancel)
    }

    func testExternalLinkOpensExternally() {
        let url = URL(string: "https://example.com")!
        XCTAssertEqual(PreviewNavigation.decision(isInitialLoad: false, navigationType: .linkActivated, url: url),
                       .openExternally(url))
    }

    func testNonHttpExternalSchemeIsCancelled() {
        for raw in ["javascript:alert(1)", "data:text/html,<b>x</b>", "file:///etc/passwd"] {
            let url = URL(string: raw)
            XCTAssertEqual(PreviewNavigation.decision(isInitialLoad: false, navigationType: .linkActivated, url: url),
                           .cancel, "\(raw) must be cancelled, never opened externally")
        }
    }
}
