import XCTest
import WebKit
@testable import MacMD

@MainActor
final class PreviewSecurityTests: XCTestCase {

    func testContentRuleListBlocksAllThenIgnoresScheme() throws {
        let json = PreviewWebView.contentRuleListJSON()
        let rules = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]]
        )
        XCTAssertGreaterThanOrEqual(rules.count, 2)

        // Rule 0 blocks every URL.
        XCTAssertEqual((rules[0]["action"] as? [String: Any])?["type"] as? String, "block")
        XCTAssertEqual((rules[0]["trigger"] as? [String: Any])?["url-filter"] as? String, ".*")

        // Rule 1 (after the block) re-allows the custom scheme.
        XCTAssertEqual((rules[1]["action"] as? [String: Any])?["type"] as? String, "ignore-previous-rules")
        let ignoreFilter = (rules[1]["trigger"] as? [String: Any])?["url-filter"] as? String ?? ""
        XCTAssertTrue(ignoreFilter.contains("macmd-resource:"))
    }

    func testContentRuleListCompiles() {
        let exp = expectation(description: "content rule list compiles")
        WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "macmd-preview-test",
            encodedContentRuleList: PreviewWebView.contentRuleListJSON()
        ) { list, error in
            XCTAssertNil(error, "the rule list JSON must be valid for WebKit")
            XCTAssertNotNil(list)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5.0)
    }
}
