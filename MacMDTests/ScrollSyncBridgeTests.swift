import XCTest
@testable import MacMD

@MainActor
final class ScrollSyncBridgeTests: XCTestCase {

    func testEditorDrivesPreview() {
        let b = ScrollSyncBridge()
        var preview: [Int] = []
        b.scrollPreviewToLine = { preview.append($0) }
        b.editorScrolled(toTopLine: 5)
        b.editorScrolled(toTopLine: 6)
        XCTAssertEqual(preview, [5, 6], "the driving side flows through freely")
    }

    func testFollowerEchoIsSuppressed() {
        let b = ScrollSyncBridge()
        var editor: [Int] = []
        var preview: [Int] = []
        b.scrollEditorToLine = { editor.append($0) }
        b.scrollPreviewToLine = { preview.append($0) }
        b.editorScrolled(toTopLine: 5)
        // The programmatic preview scroll fires the preview's own observer; that
        // echo must not drive the editor back (feedback loop).
        b.previewScrolled(toTopLine: 5)
        XCTAssertEqual(preview, [5])
        XCTAssertTrue(editor.isEmpty)
    }

    func testDriverHandsOffAfterSettling() {
        let b = ScrollSyncBridge()
        var editor: [Int] = []
        b.scrollEditorToLine = { editor.append($0) }
        b.editorScrolled(toTopLine: 1)
        let settled = expectation(description: "driver settle window elapsed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { settled.fulfill() }
        wait(for: [settled], timeout: 2.0)
        b.previewScrolled(toTopLine: 9)
        XCTAssertEqual(editor, [9], "the other side may drive once the driver is quiet")
    }
}
