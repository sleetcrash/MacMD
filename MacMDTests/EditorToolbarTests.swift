import XCTest
import AppKit
@testable import MacMD

@MainActor
final class EditorToolbarTests: XCTestCase {

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: ToolbarPref.key)
        super.tearDown()
    }

    func testParityItemsMatchFormatMenuCommands() {
        XCTAssertEqual(EditorToolbar.parityItems, [
            EditorToolbarItem(id: "bold", label: "Bold", systemImage: "bold", action: .bold),
            EditorToolbarItem(id: "italic", label: "Italic", systemImage: "italic", action: .italic),
            EditorToolbarItem(id: "strikethrough", label: "Strikethrough", systemImage: "strikethrough", action: .strikethrough),
            EditorToolbarItem(id: "code", label: "Inline Code", systemImage: "chevron.left.forwardslash.chevron.right", action: .code),
            EditorToolbarItem(id: "link", label: "Link", systemImage: "link", action: .link),
            EditorToolbarItem(id: "task", label: "Task Checkbox", systemImage: "checklist", action: .taskCheckbox),
        ])
    }

    func testToolbarItemIDsAreUniqueAndStable() {
        XCTAssertEqual(EditorToolbar.allItemIDs, ["bold", "italic", "strikethrough", "code", "link", "task"])
        XCTAssertEqual(Set(EditorToolbar.allItemIDs).count, EditorToolbar.allItemIDs.count)
    }

    func testToolbarPrefDefaultsOnPersistsAndBroadcasts() {
        UserDefaults.standard.removeObject(forKey: ToolbarPref.key)
        XCTAssertTrue(ToolbarPref.isOn, "the toolbar shows out of the box")
        let exp = expectation(forNotification: ToolbarPref.didChange, object: nil)
        ToolbarPref.set(false)
        wait(for: [exp], timeout: 1.0)
        XCTAssertFalse(ToolbarPref.isOn)
    }

    /// The toolbar reuses the SAME editor actions the Format menu drives, so
    /// each expected string matches outputs already proven in
    /// EditingCommandsTests / TaskListInteractionTests.
    func testDispatchAppliesSameEditsAsFormatMenu() {
        func editor(_ text: String, select: NSRange) -> ClickableTextView {
            let tv = ClickableTextView()
            tv.string = text
            tv.setSelectedRange(select)
            return tv
        }

        let bold = editor("hello world", select: NSRange(location: 6, length: 5))
        EditorAction.bold.invoke(on: bold)
        XCTAssertEqual(bold.string, "hello **world**")

        let italic = editor("hello world", select: NSRange(location: 0, length: 5))
        EditorAction.italic.invoke(on: italic)
        XCTAssertEqual(italic.string, "*hello* world")

        let strike = editor("hello world", select: NSRange(location: 6, length: 5))
        EditorAction.strikethrough.invoke(on: strike)
        XCTAssertEqual(strike.string, "hello ~~world~~")

        let code = editor("hello world", select: NSRange(location: 6, length: 5))
        EditorAction.code.invoke(on: code)
        XCTAssertEqual(code.string, "hello `world`")

        let link = editor("hello world", select: NSRange(location: 6, length: 5))
        EditorAction.link.invoke(on: link)
        XCTAssertEqual(link.string, "hello [world](url)")

        let task = editor("- [ ] one", select: NSRange(location: 0, length: 0))
        let highlighter = MarkdownHighlighter()   // strong ref: the view's is weak
        task.highlighter = highlighter
        EditorAction.taskCheckbox.invoke(on: task)
        XCTAssertEqual(task.string, "- [x] one")
    }
}
