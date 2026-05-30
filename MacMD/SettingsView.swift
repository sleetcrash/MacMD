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
                LabeledField(label: "Mode") {
                    ModeControl(appearanceRaw: $appearanceRaw)
                        .frame(width: modeWidth, height: rowHeight)
                }
                LabeledField(label: "Size") {
                    SizeCombo(fontSize: $fontSize)
                        .frame(width: segWidth, height: rowHeight)
                }
            }
            HStack(spacing: 14) {
                LabeledField(label: "Theme") {
                    ThemeMenu(coloring: coloring, themeId: $themeId, customs: customs,
                              onCustom: { showingCustomEditor = true })
                        .frame(width: modeWidth, height: rowHeight)
                }
                LabeledField(label: "Scheme") {
                    SchemeMenu(schemeRaw: $schemeRaw, themeId: $themeId)
                        .frame(width: segWidth, height: rowHeight)
                }
            }
            ThemePreview(coloring: coloring, palette: palette, appearance: appearance)
                .frame(maxWidth: .infinity)
        }
        .padding(EdgeInsets(top: 26, leading: 20, bottom: 20, trailing: 20))
        .frame(width: 354)
    }
}

/// Icon-only Light / Dark / System segmented control. Sun = Light, moon = Dark,
/// laptop = System. Sharp corners, the selected segment filled blue (#3478F6).
struct ModeControl: View {
    @Binding var appearanceRaw: String

    private let items: [(mode: AppAppearance, icon: String, label: String)] = [
        (.light, "sun.max", "Light"),
        (.dark, "moon.fill", "Dark"),
        (.system, "laptopcomputer", "System"),
    ]
    private let selectedBlue = Color(red: 0x34 / 255, green: 0x78 / 255, blue: 0xF6 / 255)

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                let selected = appearanceRaw == item.mode.rawValue
                Image(systemName: item.icon)
                    .font(.system(size: 13))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(selected ? selectedBlue : Color(nsColor: .textBackgroundColor))
                    .foregroundStyle(selected ? Color.white : Color.primary)
                    .overlay(index == 0 ? nil : Divider(), alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { appearanceRaw = item.mode.rawValue }
                    .accessibilityLabel(item.label)
                    .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .overlay(Rectangle().strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))
    }
}

struct Swatch: View {
    let color: Color
    var body: some View {
        color
            .frame(width: 12, height: 12)
            .overlay(Rectangle().strokeBorder(Color(white: 0.47).opacity(0.5), lineWidth: 1))
    }
}

/// The static Theme box label: name (left), the light │ dark swatch trios
/// (right, flush to the arrow), and the dropdown arrow at the right edge.
struct ThemeBoxLabel: View {
    let palette: Palette?

    var body: some View {
        HStack(spacing: 0) {
            Text(palette?.name ?? "Default")
                .font(.system(size: 11))
                .lineLimit(1)
            Spacer(minLength: 8)
            if let palette {
                HStack(spacing: 2) {
                    ForEach(Array(palette.slots.enumerated()), id: \.offset) { _, slot in
                        Swatch(color: Color(nsColor: slot.nsLight))
                    }
                    Text("|").opacity(0.35).padding(.horizontal, 2)
                    ForEach(Array(palette.slots.enumerated()), id: \.offset) { _, slot in
                        Swatch(color: Color(nsColor: slot.nsDark))
                    }
                }
            }
            Image(systemName: "chevron.down")
                .font(.system(size: 8))
                .opacity(0.5)
                .padding(.leading, 8)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(Rectangle().strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))
    }
}

/// The Theme dropdown: presets for the active scheme, a Saved group of customs
/// in that scheme, and Custom+ to open the editor. Disabled under Default.
struct ThemeMenu: View {
    let coloring: Coloring
    @Binding var themeId: String
    let customs: [Palette]
    let onCustom: () -> Void

    private var currentPalette: Palette? {
        ThemeSettings.resolvePalette(coloring: coloring, themeId: themeId, customs: customs)
    }

    var body: some View {
        Menu {
            ForEach(ColorTheming.presets(for: coloring)) { preset in
                Button(preset.name) { themeId = preset.id }
            }
            let schemeCustoms = customs.filter { $0.scheme == coloring }
            if !schemeCustoms.isEmpty {
                Divider()
                Section("Saved") {
                    ForEach(schemeCustoms) { custom in
                        Button(custom.name) { themeId = custom.id }
                    }
                }
            }
            if coloring != .off {
                Divider()
                Button("Custom+…") { onCustom() }
            }
        } label: {
            ThemeBoxLabel(palette: currentPalette)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .disabled(coloring == .off)
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
            .overlay(Rectangle().strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
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

    @MainActor final class Coordinator: NSObject, NSComboBoxDelegate {
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

/// Wraps a control with an uppercase label that fades in on hover (keeps the
/// pane clean) while always exposing the label to VoiceOver.
struct LabeledField<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content
    @State private var hovering = false

    var body: some View {
        content
            .overlay(alignment: .topLeading) {
                Text(label.uppercased())
                    .font(.system(size: 9))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
                    .opacity(hovering ? 0.55 : 0)
                    .animation(.easeInOut(duration: 0.15), value: hovering)
                    .offset(y: -14)
                    .allowsHitTesting(false)
            }
            .onHover { hovering = $0 }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(label)
    }
}
