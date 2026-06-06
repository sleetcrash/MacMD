import SwiftUI
import AppKit

@main
struct MacMDApp: App {
    @StateObject private var themeController = ThemeController()
    @StateObject private var customDraft = CustomDraft()
    @AppStorage(WordCountPref.key) private var showWordCount = false
    @AppStorage(FormattingPref.key) private var showFormatting = true

    var body: some Scene {
        DocumentGroup(newDocument: MarkdownDocument()) { file in
            DocumentView(document: file.$document)
                .environmentObject(themeController)
        }
        .commands {
            HelpCommands()
            AppSettingsCommands()
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
                Menu("Spelling and Grammar") {
                    Button("Show Spelling and Grammar") {
                        NSApp.sendAction(#selector(NSText.showGuessPanel(_:)), to: nil, from: nil)
                    }
                    .keyboardShortcut(":", modifiers: .command)
                    Button("Check Document Now") {
                        NSApp.sendAction(#selector(NSText.checkSpelling(_:)), to: nil, from: nil)
                    }
                    .keyboardShortcut(";", modifiers: .command)
                    Divider()
                    Button("Check Spelling While Typing") {
                        NSApp.sendAction(#selector(NSTextView.toggleContinuousSpellChecking(_:)), to: nil, from: nil)
                    }
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
                Button(showWordCount ? "Hide Word Count" : "Show Word Count") {
                    WordCountPref.set(!showWordCount)
                }
                Toggle("Show Formatting", isOn: Binding(
                    get: { showFormatting },
                    set: { FormattingPref.set($0) }
                ))
                .keyboardShortcut("/", modifiers: .command)
                Divider()
            }
        }

        // These three auxiliary windows are opened programmatically (Format ▸
        // Appearance, Help ▸ MacMD Help, and Custom+ in the Theme dropdown), so
        // `.commandsRemoved()` strips the open-command SwiftUI would otherwise add
        // to the Window menu. That command duplicated the Format / Help entries and
        // cluttered the Window menu; openWindow(id:) still opens each window.
        Window("Appearance", id: AppearanceScene.id) {
            SettingsView()
                .environmentObject(themeController)
                .environmentObject(customDraft)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .commandsRemoved()

        Window("Custom Theme", id: CustomThemeScene.id) {
            CustomThemeEditor()
                .environmentObject(customDraft)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .commandsRemoved()

        Window("Help", id: HelpScene.id) {
            HelpView()
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .commandsRemoved()
    }
}

/// Identifies the Appearance settings window, opened from Format ▸ Appearance.
enum AppearanceScene {
    static let id = "appearance"
}

/// The Format menu: markdown emphasis (Bold, Italic, Strikethrough, Inline
/// Code), Link, and the task-checkbox toggle, all acting on the focused editor.
/// App preferences moved to the standard app-menu Settings… item (see
/// `AppSettingsCommands`), so there is no longer a Format ▸ Appearance entry.
struct FormatCommands: Commands {
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
            Button("Strikethrough") {
                (NSApp.keyWindow?.firstResponder as? ClickableTextView)?.macmdStrikethrough(nil)
            }
            .keyboardShortcut("x", modifiers: [.command, .shift])
            Button("Inline Code") {
                (NSApp.keyWindow?.firstResponder as? ClickableTextView)?.macmdCode(nil)
            }
            Button("Link…") {
                (NSApp.keyWindow?.firstResponder as? ClickableTextView)?.macmdLink(nil)
            }
            .keyboardShortcut("k", modifiers: .command)
            Divider()
            Button("Toggle Task Checkbox") {
                (NSApp.keyWindow?.firstResponder as? ClickableTextView)?.toggleTaskCheckbox(nil)
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])
        }
    }
}

/// The app menu's Settings… item (Cmd-,), the standard macOS home for app
/// preferences. It opens the Appearance window, which holds MacMD's settings;
/// this replaces the former Format ▸ Appearance entry so there is a single home.
struct AppSettingsCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { openWindow(id: AppearanceScene.id) }
                .keyboardShortcut(",", modifiers: .command)
        }
    }
}

/// The Help menu. A single local "MacMD Help" item that opens the bundled help
/// window. No web links, to honor the offline-only design.
struct HelpCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("MacMD Help") { openWindow(id: HelpScene.id) }
                .keyboardShortcut("?", modifiers: .command)
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
