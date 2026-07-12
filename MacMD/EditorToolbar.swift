import SwiftUI
import AppKit

/// One toolbar button: a stable id (never rename; it anchors user muscle
/// memory and future customization persistence), label, SF symbol, and action.
struct EditorToolbarItem: Identifiable, Equatable {
    let id: String
    let label: String
    let systemImage: String
    let action: EditorAction
}

/// The editor commands the toolbar can invoke. Each forwards to the existing
/// Format-menu action on ClickableTextView, so no editing logic is duplicated.
enum EditorAction: Equatable {
    case bold, italic, strikethrough, code, link, taskCheckbox

    @MainActor
    func invoke(on editor: ClickableTextView) {
        switch self {
        case .bold: editor.macmdBold(nil)
        case .italic: editor.macmdItalic(nil)
        case .strikethrough: editor.macmdStrikethrough(nil)
        case .code: editor.macmdCode(nil)
        case .link: editor.macmdLink(nil)
        case .taskCheckbox: editor.toggleTaskCheckbox(nil)
        }
    }
}

/// The toolbar's command model: true parity with the Format menu (the commands
/// that actually exist), nothing invented.
enum EditorToolbar {
    static let parityItems: [EditorToolbarItem] = [
        EditorToolbarItem(id: "bold", label: "Bold", systemImage: "bold", action: .bold),
        EditorToolbarItem(id: "italic", label: "Italic", systemImage: "italic", action: .italic),
        EditorToolbarItem(id: "strikethrough", label: "Strikethrough", systemImage: "strikethrough", action: .strikethrough),
        EditorToolbarItem(id: "code", label: "Inline Code", systemImage: "chevron.left.forwardslash.chevron.right", action: .code),
        EditorToolbarItem(id: "link", label: "Link", systemImage: "link", action: .link),
        EditorToolbarItem(id: "task", label: "Task Checkbox", systemImage: "checklist", action: .taskCheckbox),
    ]

    static var allItemIDs: [String] { parityItems.map(\.id) }
}

/// The "show the format toolbar" preference. On by default; hidden from
/// Settings > Editing or View > Show Toolbar. Same UserDefaults + broadcast
/// pattern as FormattingPref (cross-window).
enum ToolbarPref {
    static let key = "showToolbar"
    static let didChange = Notification.Name("MacMDToolbarPrefDidChange")

    static var isOn: Bool {
        UserDefaults.standard.object(forKey: key) == nil
            ? true
            : UserDefaults.standard.bool(forKey: key)
    }

    static func set(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: key)
        NotificationCenter.default.post(name: didChange, object: nil)
    }
}

/// The format bar under the titlebar: Format-menu parity buttons, font family
/// and size quick controls, and a Settings shortcut.
struct EditorToolbarStrip: View {
    @EnvironmentObject private var theme: ThemeController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack(spacing: 2) {
            ForEach(EditorToolbar.parityItems) { item in
                Button {
                    if let editor = EditorFocus.resolve(in: NSApp.keyWindow) {
                        item.action.invoke(on: editor)
                    }
                } label: {
                    Image(systemName: item.systemImage)
                        .font(.system(size: 12))
                        .frame(width: 24, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help(item.label)
            }
            Divider().frame(height: 16).padding(.horizontal, 4)
            fontFamilyMenu
            sizeControls
            Spacer()
            Button {
                openWindow(id: SettingsScene.id)
            } label: {
                Image(systemName: "paintbrush")
                    .font(.system(size: 12))
                    .frame(width: 24, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help("Theme and appearance settings")
        }
        .padding(.horizontal, 8)
        .frame(height: 30)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .bottom) { Divider() }
    }

    /// Immediate-effect font family (persists at once, like the View menu's
    /// size commands); the Settings window remains the transactional home.
    private var fontFamilyMenu: some View {
        Menu {
            ForEach(FontFamily.all) { family in
                Button {
                    theme.saveFontFamily(family.id)
                } label: {
                    if family.id == theme.fontFamilyId {
                        Label(family.displayName, systemImage: "checkmark")
                    } else {
                        Text(family.displayName)
                    }
                }
            }
        } label: {
            Text(FontFamily.resolve(id: theme.fontFamilyId).displayName)
                .font(.system(size: 11))
                .lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Editor font")
    }

    private var sizeControls: some View {
        HStack(spacing: 0) {
            Button {
                theme.adjustFontSize(by: -1)
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 10))
                    .frame(width: 18, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help("Decrease font size")
            Text("\(Int(theme.fontSize))")
                .font(.system(size: 11))
                .frame(minWidth: 20)
            Button {
                theme.adjustFontSize(by: 1)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10))
                    .frame(width: 18, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help("Increase font size")
        }
        .padding(.leading, 6)
    }
}
