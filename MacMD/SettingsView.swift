import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject private var theme: ThemeController
    @Environment(\.dismiss) private var dismiss
    @AppStorage(ThemeSettings.customsKey) private var customsData = Data()
    @AppStorage(ThemeSettings.appearanceKey) private var appearanceRaw = AppAppearance.system.rawValue

    // Working copy — edits here don't reach the document until Apply/Save.
    @State private var wcSchemeRaw = Coloring.off.rawValue
    @State private var wcThemeId = ColorTheming.defaultStandardId
    @State private var wcFontSize = Double(FontSize.standard)
    @State private var showingCustomEditor = false

    private let wideWidth: CGFloat = 225
    private let segWidth: CGFloat = 75
    private let rowHeight: CGFloat = 32

    private var wcColoring: Coloring { Coloring(rawValue: wcSchemeRaw) ?? .off }
    private var appearance: AppAppearance { AppAppearance(rawValue: appearanceRaw) ?? .system }
    private var customs: [Palette] { ThemeSettings.decodeCustoms(customsData) }
    private var wcPalette: Palette? {
        ThemeSettings.resolvePalette(coloring: wcColoring, themeId: wcThemeId, customs: customs)
    }
    private var isDirty: Bool {
        wcSchemeRaw != theme.savedColoring.rawValue
        || wcThemeId != theme.savedThemeId
        || wcFontSize != theme.savedFontSize
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                LabeledField(label: "Mode") {
                    ModeControl(appearanceRaw: $appearanceRaw)
                        .frame(width: wideWidth, height: rowHeight)
                }
                LabeledField(label: "Size") {
                    SizeCombo(fontSize: $wcFontSize)
                        .frame(width: segWidth, height: rowHeight)
                }
            }
            HStack(spacing: 14) {
                LabeledField(label: "Theme") {
                    ThemeMenu(coloring: wcColoring, themeId: $wcThemeId, customs: customs,
                              onCustom: { showingCustomEditor = true })
                        .frame(width: wideWidth, height: rowHeight)
                }
                LabeledField(label: "Scheme") {
                    SchemeMenu(schemeRaw: $wcSchemeRaw, themeId: $wcThemeId)
                        .frame(width: segWidth, height: rowHeight)
                }
            }
            ThemePreview(coloring: wcColoring, palette: wcPalette, appearance: appearance)
                .frame(maxWidth: .infinity)
            HStack(spacing: 10) {
                Spacer()
                Button("Close") { dismiss() }
                    .buttonStyle(SquareButtonStyle())
                Button("Apply") { theme.apply(coloring: wcColoring, themeId: wcThemeId, fontSize: wcFontSize) }
                    .buttonStyle(SquareButtonStyle())
                    .disabled(!isDirty)
                Button("Save") { theme.save(coloring: wcColoring, themeId: wcThemeId, fontSize: wcFontSize) }
                    .buttonStyle(SquareButtonStyle())
                    .disabled(!isDirty)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(EdgeInsets(top: 26, leading: 20, bottom: 20, trailing: 20))
        .frame(width: 354)
        .background(
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { NSApp.keyWindow?.makeFirstResponder(nil) }
        )
        .onAppear { syncFromSaved() }
        .onDisappear {
            // Closing the window any way (Close button or the red X) discards
            // any unsaved Apply and snaps the document back to the saved theme.
            theme.revertToSaved()
            syncFromSaved()
        }
        .sheet(isPresented: $showingCustomEditor) {
            CustomThemeEditor(coloring: wcColoring, customsData: $customsData, selectedThemeId: $wcThemeId)
        }
    }

    private func syncFromSaved() {
        wcSchemeRaw = theme.savedColoring.rawValue
        wcThemeId = theme.savedThemeId
        wcFontSize = theme.savedFontSize
    }
}

/// Icon-only Light / Dark / System segmented control. Binds directly to the
/// persisted appearance (immediate, not part of the Apply/Save working copy).
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

/// Sharp-cornered bordered button matching the other Settings controls.
struct SquareButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12))
            .padding(.horizontal, 14)
            .frame(height: 26)
            .background(
                configuration.isPressed
                    ? Color(nsColor: .selectedControlColor)
                    : Color(nsColor: .textBackgroundColor)
            )
            .overlay(Rectangle().strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))
            .opacity(isEnabled ? 1.0 : 0.4)
            .contentShape(Rectangle())
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

/// The Theme selector: the static box label triggers a popover listing the
/// scheme's presets and saved customs, each row showing its light|dark
/// swatches (a SwiftUI popover is used instead of a native Menu because macOS
/// menu items can't render multi-color swatch images).
struct ThemeMenu: View {
    let coloring: Coloring
    @Binding var themeId: String
    let customs: [Palette]
    let onCustom: () -> Void

    @State private var showPopover = false
    @State private var hoveredId: String?

    private var currentPalette: Palette? {
        ThemeSettings.resolvePalette(coloring: coloring, themeId: themeId, customs: customs)
    }
    private var schemeCustoms: [Palette] { customs.filter { $0.scheme == coloring } }

    var body: some View {
        Button { showPopover.toggle() } label: {
            ThemeBoxLabel(palette: currentPalette)
        }
        .buttonStyle(.plain)
        .disabled(coloring == .off)
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(ColorTheming.presets(for: coloring)) { row(for: $0) }
                if !schemeCustoms.isEmpty {
                    Divider().padding(.vertical, 4)
                    ForEach(schemeCustoms) { row(for: $0) }
                }
                Divider().padding(.vertical, 4)
                rowButton(id: "__custom__", action: { showPopover = false; onCustom() }) {
                    Text("Custom+…").font(.system(size: 12))
                    Spacer()
                }
            }
            .padding(6)
            .frame(width: 250)
        }
    }

    private func row(for p: Palette) -> some View {
        rowButton(id: p.id, action: { themeId = p.id; showPopover = false }) {
            Text(p.name).font(.system(size: 12)).lineLimit(1)
            Spacer(minLength: 12)
            swatchStrip(p)
        }
    }

    @ViewBuilder
    private func swatchStrip(_ p: Palette) -> some View {
        HStack(spacing: 2) {
            ForEach(Array(p.slots.enumerated()), id: \.offset) { _, s in
                swatch(Color(nsColor: s.nsLight))
            }
            Text("|").opacity(0.35).padding(.horizontal, 1)
            ForEach(Array(p.slots.enumerated()), id: \.offset) { _, s in
                swatch(Color(nsColor: s.nsDark))
            }
        }
    }

    private func swatch(_ c: Color) -> some View {
        c.frame(width: 11, height: 11)
            .overlay(Rectangle().strokeBorder(Color(white: 0.5).opacity(0.4), lineWidth: 1))
    }

    private func rowButton<Content: View>(id: String,
                                          action: @escaping () -> Void,
                                          @ViewBuilder content: () -> Content) -> some View {
        Button(action: action) {
            HStack(spacing: 0) { content() }
                .padding(.vertical, 5)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity)
                .background(hoveredId == id ? Color.accentColor.opacity(0.25) : Color.clear)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside { hoveredId = id }
            else if hoveredId == id { hoveredId = nil }
        }
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
        DispatchQueue.main.async { [weak cb] in
            cb?.window?.makeFirstResponder(nil)
        }
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

        func controlTextDidChange(_ notification: Notification) {
            guard let cb = notification.object as? NSComboBox else { return }
            let digits = cb.stringValue.filter(\.isNumber)
            let capped = String(digits.prefix(2))
            if cb.stringValue != capped { cb.stringValue = capped }
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
