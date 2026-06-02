import SwiftUI
import AppKit

@main
struct MacMDApp: App {
    @StateObject private var themeController = ThemeController()
    @StateObject private var customDraft = CustomDraft()

    var body: some Scene {
        DocumentGroup(newDocument: MarkdownDocument()) { file in
            DocumentView(document: file.$document)
                .environmentObject(themeController)
        }
        .commands {
            CommandGroup(replacing: .help) { }
            CommandGroup(after: .textEditing) {
                Button("Toggle Task Checkbox") {
                    (NSApp.keyWindow?.firstResponder as? ClickableTextView)?.toggleTaskCheckbox(nil)
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])
            }
            CommandGroup(after: .pasteboard) {
                Menu("Find") {
                    Button("Find…") { performFindAction(.showFindInterface) }
                        .keyboardShortcut("f", modifiers: .command)
                    Button("Find and Replace…") { performFindAction(.showReplaceInterface) }
                        .keyboardShortcut("f", modifiers: [.command, .option])
                    Button("Find Next") { performFindAction(.nextMatch) }
                        .keyboardShortcut("g", modifiers: .command)
                    Button("Find Previous") { performFindAction(.previousMatch) }
                        .keyboardShortcut("g", modifiers: [.command, .shift])
                    Button("Use Selection for Find") { performFindAction(.setSearchString) }
                        .keyboardShortcut("e", modifiers: .command)
                }
            }
            CommandGroup(replacing: .printItem) {
                Button("Print…") {
                    (NSApp.keyWindow?.firstResponder as? ClickableTextView)?.macmdPrint(nil)
                }
                .keyboardShortcut("p", modifiers: .command)
            }
            FormatCommands()
            CommandGroup(after: .toolbar) {
                Button("Increase Font Size") { themeController.adjustFontSize(by: 1) }
                    .keyboardShortcut("+", modifiers: .command)
                Button("Decrease Font Size") { themeController.adjustFontSize(by: -1) }
                    .keyboardShortcut("-", modifiers: .command)
                Button("Actual Size") { themeController.resetFontSize() }
                    .keyboardShortcut("0", modifiers: .command)
                Divider()
            }
        }

        Window("Appearance", id: AppearanceScene.id) {
            SettingsView()
                .environmentObject(themeController)
                .environmentObject(customDraft)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Window("Custom Theme", id: CustomThemeScene.id) {
            CustomThemeEditor()
                .environmentObject(customDraft)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

/// Identifies the Appearance settings window, opened from Format ▸ Appearance.
enum AppearanceScene {
    static let id = "appearance"
}

/// The Format menu. Bold/Italic act on the focused editor; Appearance opens the
/// Appearance window — this replaces both the old MacMD ▸ Settings item and the
/// former Format ▸ Appearance mode submenu. Cmd-, still opens it.
struct FormatCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandMenu("Format") {
            Button("Bold") {
                (NSApp.keyWindow?.firstResponder as? ClickableTextView)?.macmdBold(nil)
            }
            .keyboardShortcut("b", modifiers: .command)
            Button("Italic") {
                (NSApp.keyWindow?.firstResponder as? ClickableTextView)?.macmdItalic(nil)
            }
            .keyboardShortcut("i", modifiers: .command)
            Divider()
            Button("Appearance") { openWindow(id: AppearanceScene.id) }
                .keyboardShortcut(",", modifiers: .command)
        }
    }
}

/// Editor font size: the persisted preference plus its bounds. Single source
/// of truth shared by the document views, the Settings pane, the View-menu
/// commands, and `Theme`'s font cache.
enum FontSize {
    static let key = "editorFontSize"
    static let standard: CGFloat = 14
    static let minimum: CGFloat = 9
    static let maximum: CGFloat = 32

    static var current: CGFloat {
        let stored = UserDefaults.standard.object(forKey: key) as? Double
        return clamp(CGFloat(stored ?? Double(standard)))
    }

    static func set(_ size: CGFloat) {
        UserDefaults.standard.set(Double(clamp(size)), forKey: key)
    }

    static func adjust(by delta: CGFloat) { set(current + delta) }
    static func reset() { set(standard) }

    static func clamp(_ size: CGFloat) -> CGFloat {
        min(maximum, max(minimum, size.rounded()))
    }
}

/// Drive the focused editor's already-active NSTextFinder from a menu command.
/// The action is carried as the sender's tag, the way the standard Find menu
/// items do it. Resolving via `keyWindow?.firstResponder` (not
/// `sendAction(_:to:nil)`) is required to reach the NSTextView hosted inside
/// the SwiftUI DocumentGroup.
@MainActor
private func performFindAction(_ action: NSTextFinder.Action) {
    let item = NSMenuItem()
    item.tag = action.rawValue
    (NSApp.keyWindow?.firstResponder as? NSTextView)?.performTextFinderAction(item)
}
