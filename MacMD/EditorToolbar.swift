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

/// The "automatically hide and show the toolbar" preference (the macOS menu-bar
/// hiding model). On by default: the toolbar stays out of the way and slides in
/// when the pointer reaches the top of the document. Off keeps it always
/// visible. Toggled from the toolbar's right-click menu and Settings > Editing.
enum ToolbarAutoHidePref {
    static let key = "toolbarAutoHide"
    static let didChange = Notification.Name("MacMDToolbarAutoHidePrefDidChange")

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

/// The format bar at the top of the document: Format-menu parity buttons, font
/// family and size quick controls, and the window chrome that used to live in
/// the titlebar, grouped left to right as formatting | font | customize, copy,
/// pane layout. Groups spread across the full width; related buttons stay
/// tight. Transparent, appearance-following, and pane-toggle height.
struct EditorToolbarStrip: View {
    /// False in preview-only layout: no editor exists, so the format buttons
    /// gray out (font and Settings controls still apply to the preview).
    var formatEnabled = true
    /// Bound to PaneModePref by the document view, so the picker stays in sync
    /// with the View menu.
    @Binding var paneMode: PaneMode
    /// Copies the document's markdown source (the document view owns the text).
    var onCopy: () -> Void
    /// True when the strip floats over the document (auto-hide reveal): it
    /// gets a translucent backing so it reads over text. Inline (always-
    /// visible) placement stays fully transparent against the window.
    var overlaid = false
    @EnvironmentObject private var theme: ThemeController
    @Environment(\.openWindow) private var openWindow
    /// Notification-backed (not @AppStorage, which does not reliably propagate
    /// across DocumentGroup windows in MacMD), so the right-click menu's
    /// checkmark stays truthful in every open window.
    @State private var autoHide = ToolbarAutoHidePref.isOn

    var body: some View {
        HStack(spacing: 2) {
            ForEach(EditorToolbar.parityItems) { item in
                Button {
                    if let editor = EditorFocus.resolve(in: NSApp.keyWindow) {
                        item.action.invoke(on: editor)
                    }
                } label: {
                    Image(systemName: item.systemImage)
                        .font(.system(size: 11))
                        .frame(width: 24, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .disabled(!formatEnabled)
                .help(item.label)
            }
            Spacer(minLength: 12)
            fontFamilyMenu
            sizeControls
            Spacer(minLength: 12)
            Button {
                openWindow(id: SettingsScene.id)
            } label: {
                Image(systemName: "paintbrush")
                    .font(.system(size: 11))
                    .frame(width: 24, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help("Customize theme and appearance")
            Button {
                onCopy()
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 11))
                    .frame(width: 24, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help("Copy the document text")
            layoutPicker
                .padding(.leading, 4)
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background {
            if overlaid {
                Rectangle().fill(.ultraThinMaterial)
            }
        }
        .contextMenu {
            Toggle("Automatically Hide Toolbar", isOn: Binding(
                get: { autoHide },
                set: { ToolbarAutoHidePref.set($0) }
            ))
        }
        .onReceive(NotificationCenter.default.publisher(for: ToolbarAutoHidePref.didChange)) { _ in
            autoHide = ToolbarAutoHidePref.isOn
        }
    }

    /// The three-way editor | split | preview control, far right by design.
    private var layoutPicker: some View {
        Picker("Layout", selection: $paneMode) {
            ForEach(PaneMode.allCases, id: \.self) { mode in
                Image(systemName: mode.systemImage)
                    .help(mode.displayName)
                    .tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .controlSize(.small)
        .help("Editor, split, or preview layout")
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
                    .frame(width: 18, height: 20)
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
                    .frame(width: 18, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help("Increase font size")
        }
        .padding(.leading, 6)
    }
}

/// An invisible strip along the document's top edge that reveals the auto-
/// hidden toolbar on hover. Tracking areas fire on geometry, independent of
/// hit-testing, so `hitTest` returns nil: clicks and typing land on the editor
/// beneath while the pointer is still noticed.
struct HoverRevealZone: NSViewRepresentable {
    var onHover: (Bool) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = TrackingView()
        view.onHover = onHover
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? TrackingView)?.onHover = onHover
    }

    final class TrackingView: NSView {
        var onHover: ((Bool) -> Void)?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                owner: self))
        }

        override func mouseEntered(with event: NSEvent) { onHover?(true) }
        override func mouseExited(with event: NSEvent) { onHover?(false) }
    }
}
