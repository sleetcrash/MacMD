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
    @State private var showingCustomEditor = false

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
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                LabeledField(label: "Mode") {
                    ModeControl(appearanceRaw: $wcAppearanceRaw)
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
            ThemePreview(coloring: wcColoring, palette: wcPalette, appearance: wcAppearance)
                .frame(maxWidth: .infinity)
            HStack(spacing: 10) {
                Spacer()
                Button("Close") { theme.revertToSaved(); dismiss() }
                    .buttonStyle(SquareButtonStyle())
                Button("Apply") {
                    theme.apply(coloring: wcColoring, themeId: wcThemeId,
                                fontSize: wcFontSize, appearance: wcAppearance)
                }
                    .buttonStyle(SquareButtonStyle())
                    .disabled(!isDirty)
                Button("Save") {
                    theme.save(coloring: wcColoring, themeId: wcThemeId,
                               fontSize: wcFontSize, appearance: wcAppearance)
                }
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
        wcAppearanceRaw = theme.savedAppearance.rawValue
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
                    .background(selected ? Color.accentColor : Color(nsColor: .textBackgroundColor))
                    .foregroundStyle(selected ? Color.white : Color.primary)
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

/// The Theme selector. Shows the static box label and, on click, pops a fully
/// opaque native menu directly below the box — connected like a real dropdown,
/// showing each theme's color swatches in the row (SwiftUI's own Menu can't
/// render multi-color images, and its menu is translucent).
struct ThemeMenu: View {
    let coloring: Coloring
    @Binding var themeId: String
    let customs: [Palette]
    let onCustom: () -> Void

    @State private var pop = false

    private var currentPalette: Palette? {
        ThemeSettings.resolvePalette(coloring: coloring, themeId: themeId, customs: customs)
    }

    private func entries() -> [MenuEntry] {
        var rows: [MenuEntry] = ColorTheming.presets(for: coloring).map { preset in
            MenuEntry(title: preset.name, image: MenuSwatch.image(for: preset)) { themeId = preset.id }
        }
        let mine = customs.filter { $0.scheme == coloring }
        for (index, custom) in mine.enumerated() {
            rows.append(MenuEntry(title: custom.name, image: MenuSwatch.image(for: custom),
                                  separatorBefore: index == 0) { themeId = custom.id })
        }
        rows.append(MenuEntry(title: "Custom+…", image: nil, separatorBefore: true, action: onCustom))
        return rows
    }

    var body: some View {
        Button { pop = true } label: {
            ThemeBoxLabel(palette: currentPalette)
        }
        .buttonStyle(.plain)
        .disabled(coloring == .off)
        .overlay(
            OpaqueMenuPopper(pop: $pop, entries: entries)
                .allowsHitTesting(false)
        )
    }
}

/// One row in an opaque dropdown: a title, an optional leading swatch image, and
/// the action to run when chosen. `separatorBefore` inserts a divider row above.
struct MenuEntry {
    let title: String
    let image: NSImage?
    var separatorBefore: Bool = false
    let action: () -> Void
}

/// Draws a theme's light | dark swatch trios as a single menu-row image.
enum MenuSwatch {
    static func image(for p: Palette) -> NSImage {
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

/// Hosts a tiny anchor view sized to its box and, when `pop` flips true, pops a
/// native menu just below it. Every row is an `OpaqueMenuRow`, so the menu reads
/// as solid instead of the system's translucent material — the whole reason for
/// the custom rows. The anchor's `window` is also forced opaque so the menu's
/// inset and corners don't show through either.
struct OpaqueMenuPopper: NSViewRepresentable {
    @Binding var pop: Bool
    let entries: () -> [MenuEntry]

    func makeNSView(context: Context) -> NSView {
        let v = FlippedAnchorView()
        context.coordinator.anchor = v
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.entries = entries
        if pop {
            DispatchQueue.main.async {
                pop = false
                context.coordinator.showMenu()
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class FlippedAnchorView: NSView {
        override var isFlipped: Bool { true }
    }

    final class Coordinator: NSObject {
        weak var anchor: NSView?
        var entries: () -> [MenuEntry] = { [] }
        private var actions: [() -> Void] = []
        private var fired = false

        func showMenu() {
            guard let anchor else { return }
            let rows = entries()
            actions = rows.map(\.action)
            fired = false

            let menu = NSMenu()
            menu.autoenablesItems = false
            let width = max(anchor.bounds.width, 1)

            for (index, row) in rows.enumerated() {
                if row.separatorBefore {
                    let sep = NSMenuItem()
                    sep.isEnabled = false
                    sep.view = OpaqueMenuRow(kind: .separator, title: "", image: nil, width: width)
                    menu.addItem(sep)
                }
                let item = NSMenuItem(title: row.title, action: #selector(pick(_:)), keyEquivalent: "")
                item.target = self
                item.tag = index
                let view = OpaqueMenuRow(kind: .item, title: row.title, image: row.image, width: width)
                view.onClick = { [weak self] in self?.fire(index) }
                item.view = view
                menu.addItem(item)
            }

            // Pop just below the box (anchor view is flipped: y = height is its bottom edge).
            menu.minimumWidth = width
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: anchor.bounds.height + 2), in: anchor)
        }

        // Keyboard activation routes here; mouse clicks route through the row's
        // onClick. Both funnel into `fire`, which runs each choice at most once.
        @objc private func pick(_ sender: NSMenuItem) { fire(sender.tag) }

        private func fire(_ index: Int) {
            guard !fired, index >= 0, index < actions.count else { return }
            fired = true
            actions[index]()
        }
    }
}

/// An opaque menu row drawn by hand so the system's translucent menu material
/// never shows through. Fills its full bounds with a solid background, draws the
/// system accent highlight on hover/keyboard selection, and renders an optional
/// leading swatch image plus the title. A `.separator` row draws a hairline
/// divider on the same opaque fill.
final class OpaqueMenuRow: NSView {
    enum Kind { case item, separator }

    private let kind: Kind
    private let title: String
    private let image: NSImage?
    private var hovering = false
    var onClick: (() -> Void)?

    init(kind: Kind, title: String, image: NSImage?, width: CGFloat) {
        self.kind = kind
        self.title = title
        self.image = image
        let height: CGFloat = kind == .separator ? 11 : 22
        super.init(frame: NSRect(x: 0, y: 0, width: max(width, 1), height: height))
        autoresizingMask = [.width]
        // A custom view replaces the menu item's native rendering, so expose
        // the row to VoiceOver explicitly (separators are decorative).
        switch kind {
        case .item:
            setAccessibilityElement(true)
            setAccessibilityRole(.menuItem)
            setAccessibilityLabel(title)
        case .separator:
            setAccessibilityElement(false)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private var showsHighlight: Bool {
        kind == .item && (hovering || (enclosingMenuItem?.isHighlighted ?? false))
    }

    override func draw(_ dirtyRect: NSRect) {
        (showsHighlight ? NSColor.selectedContentBackgroundColor : NSColor.windowBackgroundColor).setFill()
        bounds.fill()

        switch kind {
        case .separator:
            NSColor.separatorColor.setStroke()
            let line = NSBezierPath()
            line.move(to: NSPoint(x: 10, y: bounds.midY))
            line.line(to: NSPoint(x: bounds.maxX - 10, y: bounds.midY))
            line.lineWidth = 1
            line.stroke()
        case .item:
            var x: CGFloat = 14
            let cy = bounds.midY
            if let image {
                image.draw(in: NSRect(x: x, y: cy - image.size.height / 2,
                                      width: image.size.width, height: image.size.height))
                x += image.size.width + 8
            }
            let color: NSColor = showsHighlight ? .alternateSelectedControlTextColor : .labelColor
            let text = NSAttributedString(string: title, attributes: [
                .font: NSFont.menuFont(ofSize: 0),
                .foregroundColor: color,
            ])
            let size = text.size()
            text.draw(at: NSPoint(x: x, y: cy - size.height / 2))
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true }

    override func mouseUp(with event: NSEvent) {
        guard kind == .item else { return }
        enclosingMenuItem?.menu?.cancelTracking()
        onClick?()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // The menu lives in its own window; force it opaque so the inset and
        // rounded corners around the rows aren't translucent either.
        window?.isOpaque = true
        window?.backgroundColor = .windowBackgroundColor
    }
}

/// Scheme dropdown (Default / Unified / Standard). Pops the same fully opaque
/// native menu as the Theme box. Switching scheme resets the theme selection to
/// that scheme's first preset so the Theme box is never empty.
struct SchemeMenu: View {
    @Binding var schemeRaw: String
    @Binding var themeId: String

    @State private var pop = false
    private var current: Coloring { Coloring(rawValue: schemeRaw) ?? .off }

    private func entries() -> [MenuEntry] {
        Coloring.allCases.map { c in
            MenuEntry(title: c.displayName, image: nil) { select(c) }
        }
    }

    var body: some View {
        Button { pop = true } label: {
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
        .buttonStyle(.plain)
        .overlay(
            OpaqueMenuPopper(pop: $pop, entries: entries)
                .allowsHitTesting(false)
        )
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
