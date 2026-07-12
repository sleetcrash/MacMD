import XCTest
@testable import MacMD

final class TemplatesTests: XCTestCase {

    func testEveryTemplateIsNonEmptyAndEmDashFree() {
        for template in DocumentTemplate.allCases {
            XCTAssertFalse(template.text.isEmpty, "\(template.rawValue) template is empty")
            XCTAssertFalse(template.text.contains("\u{2014}"), "\(template.rawValue) contains an em dash")
            XCTAssertFalse(template.text.contains("\u{2013}"), "\(template.rawValue) contains an en dash")
        }
    }

    func testSkillAndAgentTemplatesOpenWithValidFrontMatter() {
        for template in [DocumentTemplate.skill, .agent] {
            let ns = template.text as NSString
            let span = MarkdownParser.frontMatterSpan(in: ns, fullRange: NSRange(location: 0, length: ns.length))
            XCTAssertNotNil(span, "\(template.rawValue) template must begin with a closed front-matter block")
            XCTAssertTrue(template.text.contains("name:"), "\(template.rawValue) front matter carries a name key")
            XCTAssertTrue(template.text.contains("description:"), "\(template.rawValue) front matter carries a description key")
        }
    }

    func testConfigTemplatesLeadWithATopLevelHeading() {
        XCTAssertTrue(DocumentTemplate.claudeMd.text.hasPrefix("# "))
        XCTAssertTrue(DocumentTemplate.agentsMd.text.hasPrefix("# AGENTS.md"))
    }

    func testTemplateMenuTitlesAreDistinct() {
        let titles = DocumentTemplate.allCases.map(\.menuTitle)
        XCTAssertEqual(Set(titles).count, titles.count)
    }
}
