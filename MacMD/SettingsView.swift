import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject private var theme: ThemeController
    @Environment(\.dismiss) private var dismiss
    @AppStorage(ThemeSettings.customsKey) private var customsData = Data()

    // Working copy — edits here don't reach the document until Apply/Save.
    @State private var wcSchemeRaw = Coloring.off.rawValue
    @State private var wcThemeId = ColorTheming.defaultStandardId
    @State private var wcFontSize = Double(FontSize.standard)
    @State private var wcAppearanceRaw = AppAppearance.system.rawValue
    @State private var sizeText = ""
    @State private var showingCustomEditor = false

    // Which dropdown (if any) is open, and the on-screen frame of each trigger
    // box so the in-window dropdown can sit flush beneath it.
    @State private var openMenu: MenuField?
    @State private var fieldFrames: [MenuField: CGRect] = [:]

    static let space = "settingsMenu"
    private let wideWidth: CGFloat = 225
    private let segWidth: CGFloat = 75
    private let rowHeight: CGFloat = 32

    private var wcColoring: Coloring { Coloring(rawValue: wcSchemeRaw) ?? .off }
    private var wcAppearance: AppAppearance { AppAppearance(rawValue: wcAppearanceRaw) ?? .system }
    private var customs: [Palette] { ThemeSettings.decodeCustoms(customsData) }
    private var wcPalette: Palette? {
        ThemeSettings.resolvePalette(coloring: wcColoring, themeId: wcThemeId, customs: customs)
    }
    private var isDirty: Bool {
        wcSchemeRaw != theme.savedColoring.rawValue
        || wcThemeId != theme.savedThemeId
        || wcFontSize != theme.savedFontSize
        || wcAppearanceRaw != theme.savedAppearance.rawValue
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            content
            dropdownLayer
        }
        .frame(width: 354)
        .coordinateSpace(name: Self.space)
        .onPreferenceChange(FieldFrameKey.self) { fieldFrames = $0 }
        // Drive the window's NSAppearance directly (System → nil = follow OS).
        // `.preferredColorScheme(nil)` fails to revert a previously-forced
        // light/dark window, which left the control boxes stuck in the old mode.
        .background(WindowAppearanceSetter(appearance: theme.appearance))
        .onAppear { syncFromSaved() }
        .onChange(of: openMenu) { old, new in
            // Closing the Size dropdown without committing reverts the typed
            // value to the working-copy size (Google-Docs behavior).
            if old == .size, new != .size { sizeText = "\(Int(wcFontSize))" }
        }
        .onDisappear {
            // Closing the window any way (Close button or the red X) discards
            // any unsaved Apply and snaps the document back to the saved theme.
            theme.revertToSaved()
            syncFromSaved()
        }
        .sheet(isPresented: $showingCustomEditor) {
            CustomThemeEditor(coloring: wcColoring, customsData: $customsData,
                              selectedThemeId: $wcThemeId, appearance: wcAppearance,
                              fontSize: CGFloat(wcFontSize))
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                LabeledField(label: "Mode") {
                    ModeControl(appearanceRaw: $wcAppearanceRaw)
                        .frame(width: wideWidth, height: rowHeight)
                }
                LabeledField(label: "Size") {
                    SizeControl(fontSize: $wcFontSize, text: $sizeText, openMenu: $openMenu)
                        .frame(width: segWidth, height: rowHeight)
                }
            }
            HStack(spacing: 14) {
                LabeledField(label: "Theme") {
                    themeBox.frame(width: wideWidth, height: rowHeight)
                }
                LabeledField(label: "Scheme") {
                    schemeBox.frame(width: segWidth, height: rowHeight)
                }
            }
            ThemePreview(coloring: wcColoring, palette: wcPalette,
                         appearance: wcAppearance, fontSize: CGFloat(wcFontSize))
                .frame(maxWidth: .infinity)
            HStack(spacing: 10) {
                Button("Close") { theme.revertToSaved(); dismiss() }
                    .buttonStyle(SquareButtonStyle())
                Spacer()
                Button("Apply") {
                    theme.apply(coloring: wcColoring, themeId: wcThemeId,
                                fontSize: wcFontSize, appearance: wcAppearance)
                }
                    .buttonStyle(SquareButtonStyle())
                    .disabled(!isDirty)
                Button("Save") {
                    theme.save(coloring: wcColoring, themeId: wcThemeId,
                               fontSize: wcFontSize, appearance: wcAppearance)
                    dismiss()
                }
                    .buttonStyle(SquareButtonStyle())
                    .disabled(!isDirty)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(EdgeInsets(top: 26, leading: 20, bottom: 20, trailing: 20))
    }

    // MARK: - Trigger boxes

    private var themeBox: some View {
        Button { toggle(.theme) } label: {
            ThemeBoxLabel(palette: wcPalette, isOpen: openMenu == .theme)
        }
        .buttonStyle(.plain)
        .disabled(wcColoring == .off)
        .reportsFrame(.theme)
    }

    private var schemeBox: some View {
        Button { toggle(.scheme) } label: {
            HStack(spacing: 0) {
                Text(wcColoring.displayName).font(.system(size: 11)).lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.down").font(.system(size: 8)).opacity(0.5)
                    .rotationEffect(.degrees(openMenu == .scheme ? 180 : 0))
            }
            .padding(.horizontal, 7)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
            .overlay(Rectangle().strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .reportsFrame(.scheme)
    }

    // MARK: - The in-window dropdown

    @ViewBuilder private var dropdownLayer: some View {
        if let field = openMenu, let frame = fieldFrames[field] {
            // Transparent catcher: a click anywhere outside the list closes it.
            // Also defocus, so the Size field can be re-clicked to reopen.
            Color.black.opacity(0.001)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { openMenu = nil; NSApp.keyWindow?.makeFirstResponder(nil) }
            InlineDropdown(items: items(for: field))
                .frame(width: frame.width, alignment: .topLeading)
                .fixedSize(horizontal: false, vertical: true)
                .offset(x: frame.minX, y: frame.maxY)
        }
    }

    private func items(for field: MenuField) -> [DropdownItem] {
        switch field {
        case .theme:
            var rows = ColorTheming.presets(for: wcColoring).map { p in
                DropdownItem(id: p.id, kind: .palette(p), selected: p.id == wcThemeId) { pickTheme(p.id) }
            }
            let mine = customs.filter { $0.scheme == wcColoring }
            if !mine.isEmpty {
                rows.append(DropdownItem(id: "hdr.custom", kind: .header("Custom")))
                rows.append(contentsOf: mine.map { p in
                    DropdownItem(id: p.id, kind: .palette(p), selected: p.id == wcThemeId) { pickTheme(p.id) }
                })
            }
            rows.append(DropdownItem(id: "custom.plus", kind: .customPlus(wcColoring)) {
                openMenu = nil
                showingCustomEditor = true
            })
            return rows
        case .scheme:
            return Coloring.allCases.map { c in
                DropdownItem(id: c.rawValue, kind: .text(c.displayName), selected: c == wcColoring) { pickScheme(c) }
            }
        case .size:
            return SizeControl.sizes.map { s in
                DropdownItem(id: "\(s)", kind: .text("\(s)"), selected: sizeText == "\(s)",
                             centered: true) { pickSize(s) }
            }
        }
    }

    private func toggle(_ field: MenuField) { openMenu = (openMenu == field ? nil : field) }

    private func pickTheme(_ id: String) { wcThemeId = id; openMenu = nil }

    private func pickScheme(_ c: Coloring) {
        wcSchemeRaw = c.rawValue
        switch c {
        case .off: break
        case .standard: wcThemeId = ColorTheming.defaultStandardId
        case .unified: wcThemeId = ColorTheming.defaultUnifiedId
        }
        openMenu = nil
    }

    private func pickSize(_ s: Int) {
        wcFontSize = Double(FontSize.clamp(CGFloat(s)))
        sizeText = "\(Int(wcFontSize))"
        openMenu = nil
    }

    private func syncFromSaved() {
        wcSchemeRaw = theme.savedColoring.rawValue
        wcThemeId = theme.savedThemeId
        wcFontSize = theme.savedFontSize
        wcAppearanceRaw = theme.savedAppearance.rawValue
        sizeText = "\(Int(theme.savedFontSize))"
    }

}

/// Sets the host window's NSAppearance from the *applied* Mode (the transactional
/// `theme.appearance`), so the window — and the dynamic control colors inside it —
/// only change on Apply/Save, and System reliably reverts to following the OS.
/// Uses the view's own `window`, so it always targets the Appearance window;
/// `.preferredColorScheme(nil)` failed to revert a previously-forced appearance.
struct WindowAppearanceSetter: NSViewRepresentable {
    let appearance: AppAppearance

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        let target = appearance.nsAppearance
        DispatchQueue.main.async {
            if nsView.window?.appearance != target { nsView.window?.appearance = target }
        }
    }
}

// MARK: - Dropdown plumbing

/// Identifies which trigger box a dropdown belongs to.
enum MenuField: Hashable { case theme, scheme, size }

/// Collects each trigger box's frame (in the settings coordinate space) so the
/// root overlay can place the dropdown flush beneath the right box.
struct FieldFrameKey: PreferenceKey {
    static let defaultValue: [MenuField: CGRect] = [:]
    static func reduce(value: inout [MenuField: CGRect], nextValue: () -> [MenuField: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    /// Publish this view's frame under `field`, measured in `SettingsView.space`.
    func reportsFrame(_ field: MenuField) -> some View {
        background(GeometryReader { geo in
            Color.clear.preference(key: FieldFrameKey.self,
                                   value: [field: geo.frame(in: .named(SettingsView.space))])
        })
    }
}

/// One dropdown row. `action == nil` for the non-selectable "Custom" header.
struct DropdownItem: Identifiable {
    enum Kind {
        case palette(Palette)       // name (left) + light | dark swatches (right)
        case customPlus(Coloring)   // "Custom+" + empty light | dark swatches
        case header(String)         // non-selectable subheading
        case text(String)           // plain title (scheme / size)
    }
    let id: String
    let kind: Kind
    var selected = false
    var centered = false
    var action: (() -> Void)? = nil
}

/// A seamless in-window dropdown: a flush list of rows the exact width of its
/// trigger box, sharp-edged and opaque, with no system menu chrome. It renders
/// inside the window (not a floating menu window), so it reads as attached and
/// inherits the window's light/dark Mode.
struct InlineDropdown: View {
    let items: [DropdownItem]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(items) { DropdownRow(item: $0) }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(Rectangle().strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))
    }
}

private struct DropdownRow: View {
    let item: DropdownItem
    @State private var hovering = false

    var body: some View {
        switch item.kind {
        case .header(let title):
            Text(title.uppercased())
                .font(.system(size: 9)).tracking(0.6)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.top, 7).padding(.bottom, 3)
        case .palette(let p):
            row {
                Text(p.name).font(.system(size: 11)).lineLimit(1)
                Spacer(minLength: 8)
                swatchTrio(light: p.slots.map { Color(nsColor: $0.nsLight) },
                           dark: p.slots.map { Color(nsColor: $0.nsDark) })
            }
        case .customPlus(let scheme):
            row {
                Text("Custom+").font(.system(size: 11))
                Spacer(minLength: 8)
                emptyTrio(count: scheme == .standard ? 3 : 1)
            }
        case .text(let title):
            row {
                if item.centered {
                    Text(title).font(.system(size: 11)).frame(maxWidth: .infinity, alignment: .center)
                } else {
                    Text(title).font(.system(size: 11))
                    Spacer(minLength: 0)
                }
            }
        }
    }

    @ViewBuilder private func row<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        HStack(spacing: 0, content: content)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .frame(maxWidth: .infinity)
            .background(rowBackground)
            .contentShape(Rectangle())
            // Continuous hover tracks the cursor directly (snappier than the
            // enter/exit latency of .onHover, which felt laggy).
            .onContinuousHover { phase in
                switch phase {
                case .active: hovering = true
                case .ended: hovering = false
                }
            }
            .onTapGesture { item.action?() }
    }

    private var rowBackground: Color {
        if hovering { return Color.primary.opacity(0.12) }
        if item.selected { return Color.primary.opacity(0.07) }
        return .clear
    }

    private func swatchTrio(light: [Color], dark: [Color]) -> some View {
        HStack(spacing: 2) {
            ForEach(Array(light.enumerated()), id: \.offset) { _, c in Swatch(color: c) }
            Text("|").opacity(0.35).padding(.horizontal, 2)
            ForEach(Array(dark.enumerated()), id: \.offset) { _, c in Swatch(color: c) }
        }
    }

    private func emptyTrio(count: Int) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<count, id: \.self) { _ in EmptySwatch() }
            Text("|").opacity(0.35).padding(.horizontal, 2)
            ForEach(0..<count, id: \.self) { _ in EmptySwatch() }
        }
    }
}

/// Icon-only Light / Dark / System segmented control. Binds the working copy,
/// so changing Mode only previews while the window is open; it reaches the
/// editor on Apply and persists on Save, exactly like Theme/Scheme/Size.
struct ModeControl: View {
    @Binding var appearanceRaw: String

    private let items: [(mode: AppAppearance, icon: String, label: String)] = [
        (.light, "sun.max", "Light"),
        (.dark, "moon.fill", "Dark"),
        (.system, "laptopcomputer", "System"),
    ]
    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                let selected = appearanceRaw == item.mode.rawValue
                Image(systemName: item.icon)
                    .font(.system(size: 13))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background {
                        // Selected reads as pressed-in (recessed darker surface +
                        // top inner shadow); the unselected segments get a subtle
                        // raised/lighter tint. The light-vs-dark pairing gives the
                        // selection real contrast in dark mode (where "darker on
                        // near-black" alone is invisible) without using an accent.
                        if selected {
                            Rectangle().fill(
                                Color.black.opacity(0.22)
                                    .shadow(.inner(color: .black.opacity(0.5), radius: 3, y: 1.5))
                            )
                        } else {
                            Rectangle().fill(Color.white.opacity(0.07))
                        }
                    }
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
                    .contentShape(Rectangle())
                    .onTapGesture { appearanceRaw = item.mode.rawValue }
                    .accessibilityLabel(item.label)
                    .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(Rectangle().strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))
    }
}

/// A solid 12×12 color chip with a hairline border.
struct Swatch: View {
    let color: Color
    var body: some View {
        color
            .frame(width: 12, height: 12)
            .overlay(Rectangle().strokeBorder(Color(white: 0.47).opacity(0.5), lineWidth: 1))
    }
}

/// An empty 12×12 chip (outline only) — a placeholder slot for a custom theme
/// that hasn't had a color chosen yet.
struct EmptySwatch: View {
    var body: some View {
        Rectangle()
            .fill(Color.clear)
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

/// Editable size control (Google-Docs style): a centered number field with no
/// arrow. Clicking it opens the size dropdown with the current size highlighted;
/// typing highlights a matching size live. The typed value only takes effect on
/// Return — clicking away reverts to the current size (handled by SettingsView
/// when the dropdown closes).
struct SizeControl: View {
    static let sizes = [9, 10, 11, 12, 14, 16, 18, 24, 32]

    @Binding var fontSize: Double
    @Binding var text: String
    @Binding var openMenu: MenuField?
    @State private var editing = false
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            // Show a plain (non-focusable) label until the box is clicked, so the
            // field can't grab focus — and the dropdown can't pop — when the
            // window opens. Clicking swaps in the editable field.
            if editing {
                TextField("", text: $text)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.center)
                    .focused($focused)
                    .onSubmit { commit(); openMenu = nil }
            } else {
                Text(text).frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .font(.system(size: 11))
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(Rectangle().strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture {
            editing = true
            openMenu = .size
            DispatchQueue.main.async { focused = true }
        }
        .reportsFrame(.size)
        .onChange(of: fontSize) { _, newValue in text = "\(Int(newValue))" }
        .onChange(of: openMenu) { _, new in
            if new != .size { editing = false; focused = false }
        }
    }

    private func commit() {
        let digits = text.filter(\.isNumber)
        if let value = Double(digits) {
            let clamped = FontSize.clamp(CGFloat(value))
            fontSize = Double(clamped)
            text = "\(Int(clamped))"
        } else {
            text = "\(Int(fontSize))"
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
