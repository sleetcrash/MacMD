import XCTest
import AppKit
@testable import MacMD

@MainActor
final class EditorScrollSyncTests: XCTestCase {

    private func makeEditor() -> (NSScrollView, ClickableTextView) {
        let sv = ClickableTextView.scrollableClickableTextView()
        sv.frame = NSRect(x: 0, y: 0, width: 320, height: 200)
        let tv = sv.documentView as! ClickableTextView
        tv.string = (1...40).map { "line \($0)" }.joined(separator: "\n")
        tv.layoutManager?.ensureLayout(for: tv.textContainer!)
        sv.layoutSubtreeIfNeeded()
        return (sv, tv)
    }

    func testTopVisibleLineAtTopIsOne() {
        let (_, tv) = makeEditor()
        XCTAssertEqual(tv.topVisibleLineNumber(), 1)
    }

    func testTopVisibleLineMatchesScrolledFragment() {
        let (sv, tv) = makeEditor()
        guard let lm = tv.layoutManager, let tc = tv.textContainer else { return XCTFail("no layout") }

        // Char index where line 11 begins.
        let line11Start = (((1...10).map { "line \($0)" }.joined(separator: "\n") + "\n") as NSString).length
        let glyph = lm.glyphIndexForCharacter(at: line11Start)
        let frag = lm.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)

        // Scroll so line 11's fragment sits at the top of the visible rect. The
        // fragment is in container coords; the text view offsets it by the
        // container origin.
        sv.contentView.scroll(to: NSPoint(x: 0, y: frag.minY + tv.textContainerOrigin.y))
        sv.reflectScrolledClipView(sv.contentView)
        lm.ensureLayout(for: tc)

        XCTAssertEqual(tv.topVisibleLineNumber(), 11)
    }
}
