import XCTest
@testable import MacMD

final class DocumentLayoutTests: XCTestCase {

    func testIdealWidthWidensWhenPreviewVisible() {
        let editorOnly = DocumentLayout.idealSize(previewVisible: false)
        let withPreview = DocumentLayout.idealSize(previewVisible: true)

        XCTAssertEqual(editorOnly.width, CGFloat(NewWindowSize.width))
        XCTAssertGreaterThan(withPreview.width, editorOnly.width,
                             "the two-pane split needs more natural width than editor-only")
        XCTAssertEqual(withPreview.height, editorOnly.height, "height is unchanged by the preview")
    }
}
