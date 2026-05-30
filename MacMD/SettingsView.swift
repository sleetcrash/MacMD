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
    @State private var previewAppearanceRaw = AppAppearance.system.rawValue

    private let wideWidth: CGFloat = 225
    private let segWidth: CGFloat = 75
    private let rowHeight: CGFloat = 32

    private var wcColoring: Coloring { Coloring(rawValue: wcSchemeRaw) ?? .off }
    private var appearance: AppAppearance { AppAppearance(rawValue: appearanceRaw) ?? .system }
    private var previewAppearance: AppAppearance { AppAppearance(rawValue: previewAppearanceRaw) ?? .system }
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
                    ModeControl(appearanceRaw: $previewAppearanceRaw)
                        .frame(width: wideWidth, height: rowHeight)
                }
                LabeledField(label: "Size") {
                    SizeControl(fontSize: $wcFontSize)
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
            ThemePreview(coloring: wcColoring, palette: wcPalette, appearance: previewAppearance)
                .frame(maxWidth: .infinity)
            HStack(spacing: 10) {
                Spacer()
                Button("Close") { theme.revertToSaved(); dismiss() }
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
                .onTapGesture {
                    NSApp.keyWindow?.makeFirstResponder(nil)
                }
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
        previewAppearanceRaw = appearanceRaw
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
    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                let selected = appearanceRaw == item.mode.rawValue
                Image(systemName: item.icon)
                    .font(.system(size: 13))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(selected ? Color.accentColor : Color(nsColor: .textBackgroundColor))
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
    var isOpen: Bool = false

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
                .rotationEffect(.degrees(isOpen ? 180 : 0))
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(Rectangle().strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))
    }
}

/// The Theme selector. Shows the static box label and, on click, pops a NATIVE
/// AppKit menu directly below the box — so it behaves exactly like the Scheme
/// dropdown (a real connected dropdown), while still showing each theme's color
/// swatches as a menu-item image (SwiftUI's own Menu can't render those).
struct ThemeMenu: View {
    let coloring: Coloring
    @Binding var themeId: String
    let customs: [Palette]
    let onCustom: () -> Void

    @State private var pop = false

    private var currentPalette: Palette? {
        ThemeSettings.resolvePalette(coloring: coloring, themeId: themeId, customs: customs)
    }

    var body: some View {
        Button { pop = true } label: {
            ThemeBoxLabel(palette: currentPalette)
        }
        .buttonStyle(.plain)
        .disabled(coloring == .off)
        .overlay(
            ThemeMenuPopper(pop: $pop, coloring: coloring, themeId: $themeId,
                            customs: customs, onCustom: onCustom)
                .allowsHitTesting(false)
        )
    }
}

/// Hosts a tiny anchor NSView the size of the Theme box and, when `pop` flips
/// true, pops a native NSMenu just below it. The menu items carry swatch images.
struct ThemeMenuPopper: NSViewRepresentable {
    @Binding var pop: Bool
    let coloring: Coloring
    @Binding var themeId: String
    let customs: [Palette]
    let onCustom: () -> Void

    func makeNSView(context: Context) -> NSView {
        let v = FlippedAnchorView()
        context.coordinator.anchor = v
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let c = context.coordinator
        c.coloring = coloring
        c.customs = customs
        c.onSelect = { themeId = $0 }
        c.onCustom = onCustom
        if pop {
            DispatchQueue.main.async {
                pop = false
                c.showMenu()
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class FlippedAnchorView: NSView {
        override var isFlipped: Bool { true }
    }

    final class Coordinator: NSObject {
        weak var anchor: NSView?
        var coloring: Coloring = .off
        var customs: [Palette] = []
        var onSelect: (String) -> Void = { _ in }
        var onCustom: () -> Void = {}

        func showMenu() {
            guard let anchor else { return }
            let menu = NSMenu()
            menu.autoenablesItems = false
            for preset in ColorTheming.presets(for: coloring) {
                menu.addItem(makeItem(name: preset.name, id: preset.id, palette: preset))
            }
            let mine = customs.filter { $0.scheme == coloring }
            if !mine.isEmpty {
                menu.addItem(.separator())
                for custom in mine {
                    menu.addItem(makeItem(name: custom.name, id: custom.id, palette: custom))
                }
            }
            menu.addItem(.separator())
            let customItem = NSMenuItem(title: "Custom+…", action: #selector(pickCustom), keyEquivalent: "")
            customItem.target = self
            menu.addItem(customItem)

            // Pop just below the box (anchor view is flipped: y = height is its bottom edge).
            menu.minimumWidth = anchor.bounds.width
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: anchor.bounds.height + 2), in: anchor)
        }

        private func makeItem(name: String, id: String, palette: Palette) -> NSMenuItem {
            let item = NSMenuItem(title: name, action: #selector(pick(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = id
            item.image = Coordinator.swatchImage(for: palette)
            return item
        }

        @objc private func pick(_ sender: NSMenuItem) {
            if let id = sender.representedObject as? String { onSelect(id) }
        }
        @objc private func pickCustom() { onCustom() }

        static func swatchImage(for p: Palette) -> NSImage {
            let sw: CGFloat = 12, gap: CGFloat = 2, sep: CGFloat = 6
            let n = p.slots.count
            let trio = CGFloat(n) * sw + CGFloat(max(0, n - 1)) * gap
            let width = max(1, trio + sep + trio)
            let img = NSImage(size: NSSize(width: width, height: sw))
            img.lockFocus()
            var x: CGFloat = 0
            for s in p.slots {
                s.nsLight.setFill(); NSBezierPath(rect: NSRect(x: x, y: 0, width: sw, height: sw)).fill(); x += sw + gap
            }
            x = trio + sep
            for s in p.slots {
                s.nsDark.setFill(); NSBezierPath(rect: NSRect(x: x, y: 0, width: sw, height: sw)).fill(); x += sw + gap
            }
            img.unlockFocus()
            img.isTemplate = false
            return img
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

/// Editable size control matching the square bordered style: a centered number
/// field plus a chevron menu of standard sizes. Typed values clamp to 9–32.
struct SizeControl: View {
    @Binding var fontSize: Double
    @State private var text: String = ""
    @FocusState private var focused: Bool
    private let sizes = [9, 10, 11, 12, 14, 16, 18, 24, 32]

    var body: some View {
        HStack(spacing: 2) {
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.center)
                .font(.system(size: 11))
                .focused($focused)
                .onSubmit(commit)
                .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
            Menu {
                ForEach(sizes, id: \.self) { s in
                    Button("\(s)") { fontSize = Double(s); text = "\(s)" }
                }
            } label: {
                Image(systemName: "chevron.down").font(.system(size: 8)).opacity(0.5)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(Rectangle().strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))
        .onAppear { text = "\(Int(fontSize))" }
        .onChange(of: fontSize) { _, newValue in text = "\(Int(newValue))" }
    }

    private func commit() {
        let digits = text.filter(\.isNumber)
        let value = CGFloat(Double(digits) ?? fontSize)
        let clamped = FontSize.clamp(value)
        fontSize = Double(clamped)
        text = "\(Int(clamped))"
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
