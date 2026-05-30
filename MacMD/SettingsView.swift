import SwiftUI
import AppKit

struct SettingsView: View {
    @AppStorage(FontSize.key) private var fontSize = Double(FontSize.standard)
    @AppStorage(ThemeSettings.schemeKey) private var schemeRaw = Coloring.off.rawValue
    @AppStorage(ThemeSettings.themeIdKey) private var themeId = ColorTheming.defaultStandardId
    @AppStorage(ThemeSettings.appearanceKey) private var appearanceRaw = AppAppearance.system.rawValue
    @AppStorage(ThemeSettings.customsKey) private var customsData = Data()
    @State private var showingCustomEditor = false

    // Static sizing from the locked mock.
    private let modeWidth: CGFloat = 225
    private let segWidth: CGFloat = 75
    private let rowHeight: CGFloat = 32

    private var coloring: Coloring { Coloring(rawValue: schemeRaw) ?? .off }
    private var appearance: AppAppearance { AppAppearance(rawValue: appearanceRaw) ?? .system }
    private var customs: [Palette] { ThemeSettings.decodeCustoms(customsData) }
    private var palette: Palette? {
        ThemeSettings.resolvePalette(coloring: coloring, themeId: themeId, customs: customs)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                // Mode placeholder (Task 12)
                Color(nsColor: .controlBackgroundColor)
                    .frame(width: modeWidth, height: rowHeight)
                    .overlay(Rectangle().strokeBorder(Color.black.opacity(0.22), lineWidth: 1))
                SizeCombo(fontSize: $fontSize)
                    .frame(width: segWidth, height: rowHeight)
            }
            HStack(spacing: 14) {
                // Theme placeholder (Task 13)
                Color(nsColor: .textBackgroundColor)
                    .frame(width: modeWidth, height: rowHeight)
                    .overlay(Rectangle().strokeBorder(Color.black.opacity(0.25), lineWidth: 1))
                SchemeMenu(schemeRaw: $schemeRaw, themeId: $themeId)
                    .frame(width: segWidth, height: rowHeight)
            }
            // Preview placeholder (Task 14)
            Color(nsColor: .textBackgroundColor)
                .frame(height: 120)
                .frame(maxWidth: .infinity)
                .overlay(Rectangle().strokeBorder(Color.black.opacity(0.12), lineWidth: 1))
        }
        .padding(20)
        .frame(width: 354)
    }
}

/// Scheme dropdown (Default / Unified / Standard). Switching scheme resets the
/// theme selection to that scheme's first preset so the Theme box is never empty.
struct SchemeMenu: View {
    @Binding var schemeRaw: String
    @Binding var themeId: String

    private var current: Coloring { Coloring(rawValue: schemeRaw) ?? .off }

    var body: some View {
        Menu {
            ForEach(Coloring.allCases, id: \.self) { c in
                Button(c.displayName) { select(c) }
            }
        } label: {
            HStack(spacing: 0) {
                Text(current.displayName).font(.system(size: 11)).lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.down").font(.system(size: 8)).opacity(0.5)
            }
            .padding(.horizontal, 7)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
            .overlay(Rectangle().strokeBorder(Color.black.opacity(0.25), lineWidth: 1))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
    }

    private func select(_ c: Coloring) {
        schemeRaw = c.rawValue
        switch c {
        case .off: break
        case .standard: themeId = ColorTheming.defaultStandardId
        case .unified: themeId = ColorTheming.defaultUnifiedId
        }
    }
}

/// Editable size combo: pick a standard size or type any value 9–32 (clamped).
/// Shows the number only, centered. Backed by the existing FontSize preference.
struct SizeCombo: NSViewRepresentable {
    @Binding var fontSize: Double
    private let sizes: [Int] = [9, 10, 11, 12, 14, 16, 18, 24, 32]

    func makeNSView(context: Context) -> NSComboBox {
        let cb = NSComboBox()
        cb.isEditable = true
        cb.completes = false
        cb.usesDataSource = false
        cb.addItems(withObjectValues: sizes.map { "\($0)" })
        cb.delegate = context.coordinator
        cb.alignment = .center
        cb.font = .systemFont(ofSize: 11)
        cb.stringValue = "\(Int(fontSize))"
        return cb
    }

    func updateNSView(_ cb: NSComboBox, context: Context) {
        let s = "\(Int(fontSize))"
        if cb.stringValue != s { cb.stringValue = s }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSComboBoxDelegate {
        let parent: SizeCombo
        init(_ parent: SizeCombo) { self.parent = parent }

        private func commit(_ cb: NSComboBox) {
            let raw = CGFloat(Double(cb.stringValue) ?? parent.fontSize)
            let clamped = FontSize.clamp(raw)
            parent.fontSize = Double(clamped)
            cb.stringValue = "\(Int(clamped))"
        }

        func comboBoxSelectionDidChange(_ notification: Notification) {
            guard let cb = notification.object as? NSComboBox else { return }
            // objectValueOfSelectedItem is updated after this fires; defer.
            DispatchQueue.main.async {
                if let value = cb.objectValueOfSelectedItem as? String {
                    cb.stringValue = value
                }
                self.commit(cb)
            }
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let cb = notification.object as? NSComboBox else { return }
            commit(cb)
        }
    }
}
