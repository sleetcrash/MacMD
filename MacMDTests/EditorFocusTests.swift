import XCTest
import AppKit
@testable import MacMD

@MainActor
final class EditorFocusTests: XCTestCase {

    private func makeWindow() -> NSWindow {
        NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                 styleMask: [.titled], backing: .buffered, defer: false)
    }

    func testResolvesEditorWhenAnotherViewIsFirstResponder() {
        let window = makeWindow()
        let container = NSView()
        let sibling = NSTextView()          // a plain focusable text view, not the editor
        let inner = NSView()
        let editor = ClickableTextView()    // the real editor, buried a level down
        inner.addSubview(editor)
        container.addSubview(sibling)
        container.addSubview(inner)
        window.contentView = container
        _ = window.makeFirstResponder(sibling)

        XCTAssertTrue(EditorFocus.resolve(in: window) === editor)
    }

    func testReturnsFirstResponderEditorDirectly() {
        let window = makeWindow()
        let editor = ClickableTextView()
        let container = NSView()
        container.addSubview(editor)
        window.contentView = container
        _ = window.makeFirstResponder(editor)

        XCTAssertTrue(EditorFocus.resolve(in: window) === editor)
    }

    func testReturnsNilWhenNoEditorInTree() {
        let window = makeWindow()
        let container = NSView()
        container.addSubview(NSTextView())
        window.contentView = container

        XCTAssertNil(EditorFocus.resolve(in: window))
    }
}
