import SwiftUI
import AppKit

@main
struct MacMDApp: App {
    @StateObject private var themeController = ThemeController()
    @StateObject private var customDraft = CustomDraft()
    @AppStorage(WordCountPref.key) private var showWordCount = false
    @AppStorage(FormattingPref.key) private var showFormatting = true
    @AppStorage(LineNumbersPref.key) private var showLineNumbers = true
    @AppStorage(ToolbarPref.key) private var showToolbar = true
    @AppStorage(PaneModePref.key) private var paneModeRaw = PaneMode.editor.rawValue
    @AppStorage(SpellingPref.spellingKey) private var checkSpelling = true
    @AppStorage(SpellingPref.grammarKey) private var checkGrammar = false

    init() {
        PaneModePref.migrate()
    }

    private var paneMode: PaneMode { PaneMode(rawValue: paneModeRaw) ?? .editor }

    var body: some Scene {
        DocumentGroup(newDocument: MarkdownDocument()) { file in
            // fileURL is nil for a brand-new Untitled document; those windows
            // get the preferred New Windows size, while reopened files keep
            // whatever frame macOS restores for them.
            DocumentView(document: file.$document, isNewDocument: file.fileURL == nil,
                         documentDirectory: file.fileURL?.deletingLastPathComponent())
                .environmentObject(themeController)
        }
        .commands {
            HelpCommands()
            AppSettingsCommands()
            TemplateCommands()
            CommandGroup(after: .importExport) {
                Button("Export to HTML…") {
                    if let editor = focusedEditor() {
                        HTMLExporter.export(markdown: editor.string, theme: themeController, in: editor.window)
                    }
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                Button("Export to PDF…") {
                    if let editor = focusedEditor() {
                        PDFExporter.export(markdown: editor.string, theme: themeController, in: editor.window)
                    }
                }
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
                    // Pref-bound toggles (not per-view NSTextView actions) so the
                    // change persists and reaches every open editor at once.
                    Toggle("Check Spelling While Typing", isOn: Binding(
                        get: { checkSpelling },
                        set: { SpellingPref.setCheckSpelling($0) }
                    ))
                    Toggle("Check Grammar With Spelling", isOn: Binding(
                        get: { checkGrammar },
                        set: { SpellingPref.setCheckGrammar($0) }
                    ))
                }
            }
            CommandGroup(replacing: .printItem) {
                Button("Print…") {
                    focusedEditor()?.macmdPrint(nil)
                }
                .keyboardShortcut("p", modifiers: .command)
            }
            FormatCommands()
            CommandGroup(after: .toolbar) {
                Button("Increase Font Size") { themeController.adjustFontSize(by: 1) }
                    .keyboardShortcut("+", modifiers: .command)
                Button("Decrease Font Size") { themeController.adjustFontSize(by: -1) }
                    .keyboardShortcut("-", modifiers: .command)
                Button("Reset Font Size") { themeController.resetFontSize() }
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
                Toggle("Show Line Numbers", isOn: Binding(
                    get: { showLineNumbers },
                    set: { LineNumbersPref.set($0) }
                ))
                Toggle("Show Toolbar", isOn: Binding(
                    get: { showToolbar },
                    set: { ToolbarPref.set($0) }
                ))
                Toggle("Show Preview", isOn: Binding(
                    get: { paneMode != .editor },
                    set: { PaneModePref.set($0 ? .split : .editor) }
                ))
                .keyboardShortcut("p", modifiers: [.command, .shift])
                Picker("Layout", selection: Binding(
                    get: { paneMode },
                    set: { PaneModePref.set($0) }
                )) {
                    ForEach(PaneMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                Divider()
            }
        }

        // These three auxiliary windows are opened programmatically (MacMD ▸
        // Settings, Help ▸ MacMD Help, and Custom+ in the Theme dropdown), so
        // `.commandsRemoved()` strips the open-command SwiftUI would otherwise add
        // to the Window menu. That command duplicated the app-menu / Help entries
        // and cluttered the Window menu; openWindow(id:) still opens each window.
        Window("Settings", id: SettingsScene.id) {
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

/// Identifies the Settings window (titled "Appearance" before 1.4.2), opened
/// from MacMD ▸ Settings. The scene id stays "appearance" so the window's
/// saved frame survives the rename.
enum SettingsScene {
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
                focusedEditor()?.macmdBold(nil)
            }
            .keyboardShortcut("b", modifiers: .command)
            Button("Italic") {
                focusedEditor()?.macmdItalic(nil)
            }
            .keyboardShortcut("i", modifiers: .command)
            Button("Strikethrough") {
                focusedEditor()?.macmdStrikethrough(nil)
            }
            .keyboardShortcut("x", modifiers: [.command, .shift])
            Button("Inline Code") {
                focusedEditor()?.macmdCode(nil)
            }
            Button("Link…") {
                focusedEditor()?.macmdLink(nil)
            }
            .keyboardShortcut("k", modifiers: .command)
            Divider()
            Button("Toggle Task Checkbox") {
                focusedEditor()?.toggleTaskCheckbox(nil)
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])
        }
    }
}

/// The app menu's Settings… item (Cmd-,), the standard macOS home for app
/// preferences. It opens the Settings window, which holds MacMD's settings;
/// this replaces the former Format ▸ Appearance entry so there is a single home.
struct AppSettingsCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { openWindow(id: SettingsScene.id) }
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

/// Resolves the document editor regardless of which pane holds first responder.
/// Once the preview, outline, or workspace sidebar can take first responder, the
/// key window's first responder may no longer be the editor, so Format/Find/Print
/// must descend the view tree to find it rather than only checking the responder.
@MainActor
enum EditorFocus {
    static func resolve(in window: NSWindow?) -> ClickableTextView? {
        guard let window else { return nil }
        if let editor = window.firstResponder as? ClickableTextView { return editor }
        return window.contentView.flatMap(firstEditor(in:))
    }

    private static func firstEditor(in view: NSView) -> ClickableTextView? {
        if let editor = view as? ClickableTextView { return editor }
        for subview in view.subviews {
            if let found = firstEditor(in: subview) { return found }
        }
        return nil
    }
}

/// The markdown editor that currently holds keyboard focus, or nil. Menu commands
/// resolve their target this way because `sendAction(_:to:nil)` does not reach an
/// NSTextView hosted inside the SwiftUI DocumentGroup.
@MainActor
private func focusedEditor() -> ClickableTextView? {
    EditorFocus.resolve(in: NSApp.keyWindow)
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
    EditorFocus.resolve(in: NSApp.keyWindow)?.performTextFinderAction(item)
}
