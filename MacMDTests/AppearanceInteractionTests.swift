import XCTest
@testable import MacMD

/// Pure-logic tests for the Appearance window's interaction helpers. The AppKit
/// and SwiftUI glue that applies them is verified live. Currently covers
/// `WindowPlacement` (keeping an auxiliary window fully on-screen).
final class AppearanceInteractionTests: XCTestCase {

    // MARK: - WindowPlacement.onScreen

    private let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)

    func testOnScreenLeavesAFullyVisibleFrameUntouched() {
        // A window the user dragged somewhere fully on-screen must not move, so
        // drag-to-reposition keeps sticking.
        let f = CGRect(x: 100, y: 120, width: 354, height: 400)
        XCTAssertEqual(WindowPlacement.onScreen(f, in: visible), f)
    }

    func testOnScreenPullsAFrameOffTheRightEdgeBack() {
        let f = CGRect(x: 1300, y: 120, width: 354, height: 400)
        let fixed = WindowPlacement.onScreen(f, in: visible)
        XCTAssertEqual(fixed.maxX, visible.maxX, accuracy: 0.001)   // flush right
        XCTAssertEqual(fixed.minY, 120, accuracy: 0.001)           // Y untouched
        XCTAssertEqual(fixed.size, f.size)
    }

    func testOnScreenPullsAFrameOffTheLeftEdgeBack() {
        let f = CGRect(x: -80, y: 120, width: 354, height: 400)
        let fixed = WindowPlacement.onScreen(f, in: visible)
        XCTAssertEqual(fixed.minX, visible.minX, accuracy: 0.001)
    }

    func testOnScreenPullsAFrameOffTheTopBack() {
        // maxY past the top (menu bar) — slide down so the title bar shows.
        let f = CGRect(x: 100, y: 700, width: 354, height: 400)   // maxY = 1100
        let fixed = WindowPlacement.onScreen(f, in: visible)
        XCTAssertEqual(fixed.maxY, visible.maxY, accuracy: 0.001)
        XCTAssertEqual(fixed.minX, 100, accuracy: 0.001)          // X untouched
    }

    func testOnScreenPullsAFrameOffTheBottomBack() {
        let f = CGRect(x: 100, y: -60, width: 354, height: 400)
        let fixed = WindowPlacement.onScreen(f, in: visible)
        XCTAssertEqual(fixed.minY, visible.minY, accuracy: 0.001)
    }

    func testOnScreenPinsAnOverwideFrameToTheLeftEdge() {
        let f = CGRect(x: 100, y: 120, width: 2000, height: 400)
        let fixed = WindowPlacement.onScreen(f, in: visible)
        XCTAssertEqual(fixed.minX, visible.minX, accuracy: 0.001)
        XCTAssertEqual(fixed.minY, 120, accuracy: 0.001)   // Y untouched
        XCTAssertEqual(fixed.size, f.size)                 // never resized
    }

    func testOnScreenKeepsTheTitleBarOfAnOvertallFrameReachable() {
        let f = CGRect(x: 100, y: 120, width: 354, height: 1000)
        let fixed = WindowPlacement.onScreen(f, in: visible)
        XCTAssertEqual(fixed.maxY, visible.maxY, accuracy: 0.001)   // top stays on screen
        XCTAssertEqual(fixed.minX, 100, accuracy: 0.001)           // X untouched
        XCTAssertEqual(fixed.size, f.size)                         // never resized
    }

    func testOnScreenRespectsANonZeroVisibleOrigin() {
        // visibleFrame excludes the Dock/menu bar, so its origin isn't (0,0).
        let dockVisible = CGRect(x: 0, y: 64, width: 1440, height: 812)
        let f = CGRect(x: 100, y: 0, width: 354, height: 400)   // minY below the Dock
        let fixed = WindowPlacement.onScreen(f, in: dockVisible)
        XCTAssertEqual(fixed.minY, dockVisible.minY, accuracy: 0.001)
    }

    // MARK: - InlineDropdown keyboard / hover index math

    private func textItem(_ id: String) -> DropdownItem {
        DropdownItem(id: id, kind: .text(id), action: {})
    }
    private func headerItem(_ id: String) -> DropdownItem {
        DropdownItem(id: id, kind: .header(id))   // action == nil → non-selectable
    }

    func testNextSelectableStartsAtFirstWhenNoCurrentMovingDown() {
        let items = [textItem("a"), textItem("b"), textItem("c")]
        XCTAssertEqual(InlineDropdown.nextSelectable(from: nil, step: 1, items: items), 0)
    }

    func testNextSelectableStartsAtLastWhenNoCurrentMovingUp() {
        let items = [textItem("a"), textItem("b"), textItem("c")]
        XCTAssertEqual(InlineDropdown.nextSelectable(from: nil, step: -1, items: items), 2)
    }

    func testNextSelectableMovesDownThenClampsAtTheEnd() {
        let items = [textItem("a"), textItem("b"), textItem("c")]
        XCTAssertEqual(InlineDropdown.nextSelectable(from: 0, step: 1, items: items), 1)
        XCTAssertEqual(InlineDropdown.nextSelectable(from: 2, step: 1, items: items), 2)   // clamp
    }

    func testNextSelectableMovesUpThenClampsAtTheStart() {
        let items = [textItem("a"), textItem("b"), textItem("c")]
        XCTAssertEqual(InlineDropdown.nextSelectable(from: 2, step: -1, items: items), 1)
        XCTAssertEqual(InlineDropdown.nextSelectable(from: 0, step: -1, items: items), 0)   // clamp
    }

    func testNextSelectableSkipsHeaders() {
        // a(0) | header(1) | b(2)
        let items = [textItem("a"), headerItem("hdr"), textItem("b")]
        XCTAssertEqual(InlineDropdown.nextSelectable(from: 0, step: 1, items: items), 2)
        XCTAssertEqual(InlineDropdown.nextSelectable(from: 2, step: -1, items: items), 0)
    }

    func testNextSelectableSkipsALeadingHeaderForTheInitialDown() {
        let items = [headerItem("hdr"), textItem("a"), textItem("b")]
        XCTAssertEqual(InlineDropdown.nextSelectable(from: nil, step: 1, items: items), 1)
    }

    func testNextSelectableReturnsNilWhenNothingSelectable() {
        XCTAssertNil(InlineDropdown.nextSelectable(from: nil, step: 1, items: [headerItem("h")]))
        XCTAssertNil(InlineDropdown.nextSelectable(from: nil, step: 1, items: []))
    }

    func testRowIndexMapsContentYToTheRowAtThatOffset() {
        // three 24pt rows: a 0..24, b 24..48, c 48..72
        let items = [textItem("a"), textItem("b"), textItem("c")]
        XCTAssertEqual(InlineDropdown.rowIndex(atContentY: 10, items: items), 0)
        XCTAssertEqual(InlineDropdown.rowIndex(atContentY: 30, items: items), 1)
        XCTAssertEqual(InlineDropdown.rowIndex(atContentY: 60, items: items), 2)
    }

    func testRowIndexReturnsNilOutsideTheContent() {
        let items = [textItem("a"), textItem("b")]
        XCTAssertNil(InlineDropdown.rowIndex(atContentY: -5, items: items))
        XCTAssertNil(InlineDropdown.rowIndex(atContentY: 999, items: items))
    }

    func testRowIndexReturnsNilOverANonSelectableHeader() {
        // a(24) 0..24, header(21) 24..45, b(24) 45..69
        let items = [textItem("a"), headerItem("hdr"), textItem("b")]
        XCTAssertNil(InlineDropdown.rowIndex(atContentY: 32, items: items))   // in the header band
        XCTAssertEqual(InlineDropdown.rowIndex(atContentY: 50, items: items), 2)
    }
}
