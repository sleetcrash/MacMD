import SwiftUI
import AppKit

@main
struct MacMDApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: MarkdownDocument()) { file in
            DocumentView(document: file.$document)
        }
        .commands {
            CommandGroup(replacing: .help) { }
            CommandGroup(after: .textEditing) {
                Button("Toggle Task Checkbox") {
                    (NSApp.keyWindow?.firstResponder as? ClickableTextView)?.toggleTaskCheckbox(nil)
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])
            }
            CommandGroup(after: .toolbar) {
                Button("Increase Font Size") { FontSize.adjust(by: 1) }
                    .keyboardShortcut("+", modifiers: .command)
                Button("Decrease Font Size") { FontSize.adjust(by: -1) }
                    .keyboardShortcut("-", modifiers: .command)
                Button("Actual Size") { FontSize.reset() }
                    .keyboardShortcut("0", modifiers: .command)
                Divider()
            }
        }

        Settings {
            SettingsView()
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

struct SettingsView: View {
    @AppStorage(FontSize.key) private var fontSize = Double(FontSize.standard)

    var body: some View {
        Form {
            Stepper(value: $fontSize,
                    in: Double(FontSize.minimum)...Double(FontSize.maximum),
                    step: 1) {
                Text("Editor font size: \(Int(fontSize)) pt")
            }
            Button("Reset to Default") { fontSize = Double(FontSize.standard) }
        }
        .padding(20)
        .frame(width: 320)
    }
}
