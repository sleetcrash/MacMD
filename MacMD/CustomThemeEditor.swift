import SwiftUI
import AppKit

/// Identifies the Custom Theme window, opened from the Theme dropdown's Custom+.
enum CustomThemeScene {
    static let id = "customTheme"
}

/// Shared, observable draft of the custom theme being edited. Lives in the app
/// and is injected into both the Appearance window and the Custom Theme window,
/// so editing colors here drives the Appearance window's live preview.
@MainActor
final class CustomDraft: ObservableObject {
    @Published var active = false
    @Published var scheme: Coloring = .standard
    @Published var name = ""
    @Published var editingId: String?
    // Default to the standard scheme's three slots so the initial state is
    // self-consistent (scheme → slotCount → array counts) before begin/beginEditing.
    @Published var lights: [Color] = [.black, .black, .black]
    @Published var darks: [Color] = [.white, .white, .white]
    /// Set to the id just saved/applied, so the Appearance window can select it.
    @Published var savedId: String?
    /// (side, slot) of the swatch whose color well is the active panel target, so
    /// only that swatch draws a selection ring. nil = nothing selected.
    @Published var selectedWell: SelectedWell?

    enum Side: Equatable { case light, dark }
    struct SelectedWell: Equatable { var side: Side; var slot: Int }

    var slotCount: Int { scheme == .standard ? 3 : 1 }

    /// Start a brand-new custom theme for `scheme`.
    func begin(scheme: Coloring) {
        self.scheme = scheme
        let count = scheme == .standard ? 3 : 1
        name = ""
        editingId = nil
        // Default to black (light) / white (dark) so the preview shows the
        // default look until a swatch is given a color.
        lights = Array(repeating: .black, count: count)
        darks = Array(repeating: .white, count: count)
        savedId = nil
        selectedWell = nil
        active = true
    }

    /// Load an existing saved custom palette back into the editor (the pencil
    /// affordance on a custom dropdown row).
    func beginEditing(_ palette: Palette) {
        scheme = palette.scheme
        name = palette.name
        editingId = palette.id
        lights = palette.slots.map { Color(nsColor: $0.nsLight) }
        darks = palette.slots.map { Color(nsColor: $0.nsDark) }
        savedId = nil
        selectedWell = nil
        active = true
    }

    func end() { active = false; selectedWell = nil }

    /// The in-progress palette, for the Appearance window's preview.
    var palette: Palette {
        let slots = (0..<slotCount).map { i in
            ColorPair(light: CustomDraft.hex(lights[i]), dark: CustomDraft.hex(darks[i]))
        }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return Palette(id: editingId ?? "draft.custom",
                       name: trimmed.isEmpty ? "Custom" : trimmed,
                       scheme: scheme, slots: slots)
    }

    static func hex(_ color: Color) -> String {
        let ns = NSColor(color)
        return (ns.usingColorSpace(.sRGB) ?? ns).hexString
    }
}

/// The Custom Theme editor, a separate window styled as an extension of the
/// Appearance window (same neutral chrome, sharp edges, square buttons). It has
/// no preview of its own; editing colors live-updates the Appearance window's
/// preview through the shared `CustomDraft`. Save commits the palette to the
/// theme library and selects it in the Appearance window (apply it to the
/// document from there, like any preset); Close (or the red X) returns to the
/// Appearance window.
struct CustomThemeEditor: View {
    @EnvironmentObject private var draft: CustomDraft
    @AppStorage(ThemeSettings.customsKey) private var customsData = Data()
    @Environment(\.dismiss) private var dismiss

    private let wellSize: CGFloat = 24
    @State private var showDeleteConfirm = false
    static let deleteRed = Color(red: 0.80, green: 0.25, blue: 0.27)

    private var slotLabels: [String] { draft.scheme == .standard ? ["H1", "H2", "H3"] : ["Color"] }
    // The slot count that is safe to index across every per-slot array, guarding
    // renders during a scheme change (or any momentarily inconsistent state).
    private var safeCount: Int { min(draft.lights.count, draft.darks.count, slotLabels.count) }
    private var canSave: Bool { !draft.name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        ZStack {
            editor
            if showDeleteConfirm { deleteConfirmation }
        }
        .frame(width: 264)   // hugs the swatch row; no Close button to widen for
        .background(Pane.window)
        .background(SystemWindowAppearance())
        .background(PositionBesideAppearance())
        .background(RaiseOnOpen())
        .background(FloatAboveDocument())
        .onExitCommand {
            if showDeleteConfirm { showDeleteConfirm = false } else { dismiss() }
        }
        .onDisappear {
            draft.end()
            // Close the color picker and hand focus back to the Appearance window
            // (not the document) however this window was dismissed, but only if
            // Appearance is still on screen. When Appearance is the one closing (it
            // cascades this window shut), re-showing it here would resurrect a
            // closing window, so skip the re-focus in that case.
            NSColorPanel.shared.orderOut(nil)
            NSColorPanel.shared.level = .normal   // undo the floating level set while picking
            if let appWin = NSApp.windows.first(where: { $0.title == "Appearance" }), appWin.isVisible {
                appWin.makeKeyAndOrderFront(nil)
            }
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Custom Theme")
                .font(.system(size: 12, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .center)

            // One swatch row laid out like the Appearance theme box: light trio │
            // dark trio, with a sun (left) and moon (right) marking which is which.
            // Heading labels sit centered above each swatch; the Name field spans
            // the swatch columns just below them. The grid and header are centered.
            Grid(alignment: .center, horizontalSpacing: 6, verticalSpacing: 8) {
                GridRow {
                    Text("")
                    ForEach(0..<safeCount, id: \.self) { i in
                        Text(slotLabels[i]).font(.system(size: 10)).foregroundStyle(Pane.muted)
                    }
                    Text("")
                    ForEach(0..<safeCount, id: \.self) { i in
                        Text(slotLabels[i]).font(.system(size: 10)).foregroundStyle(Pane.muted)
                    }
                    Text("")
                }
                GridRow {
                    Image(systemName: "sun.max").font(.system(size: 12)).foregroundStyle(Pane.muted)
                        .accessibilityLabel("Light")
                    ForEach(0..<safeCount, id: \.self) { i in
                        SquareColorWell(color: $draft.lights[i], size: wellSize,
                                        isSelected: draft.selectedWell == CustomDraft.SelectedWell(side: .light, slot: i)) {
                            draft.selectedWell = CustomDraft.SelectedWell(side: .light, slot: i)
                        }
                        .accessibilityLabel("\(slotLabels[i]) light color")
                    }
                    Text("|").opacity(0.35)
                    ForEach(0..<safeCount, id: \.self) { i in
                        SquareColorWell(color: $draft.darks[i], size: wellSize,
                                        isSelected: draft.selectedWell == CustomDraft.SelectedWell(side: .dark, slot: i)) {
                            draft.selectedWell = CustomDraft.SelectedWell(side: .dark, slot: i)
                        }
                        .accessibilityLabel("\(slotLabels[i]) dark color")
                    }
                    Image(systemName: "moon.fill").font(.system(size: 12)).foregroundStyle(Pane.muted)
                        .accessibilityLabel("Dark")
                }
                GridRow {
                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])   // sun column
                    TextField("Name", text: $draft.name)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .padding(.horizontal, 8)
                        .frame(height: 26)
                        .frame(maxWidth: .infinity)
                        .background(Pane.field)
                        .overlay(Rectangle().strokeBorder(Pane.border, lineWidth: 1))
                        .onChange(of: draft.name) { _, v in if v.count > 10 { draft.name = String(v.prefix(10)) } }
                        .padding(.top, 6)
                        .gridCellColumns(safeCount * 2 + 1)   // L1 ... D3: spans the 6 swatches + divider
                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])   // moon column
                }
            }
            .frame(maxWidth: .infinity)

            // Save sits bottom-right and Delete (red outline, only when editing a
            // saved theme) bottom-left, at the window margins -- the macOS-standard
            // action placement. The title-bar close button dismisses the window, so
            // there is no separate Close button to duplicate it.
            HStack(spacing: 10) {
                if draft.editingId != nil {
                    Button("Delete") { showDeleteConfirm = true }
                        .buttonStyle(SquareButtonStyle(outline: Self.deleteRed))
                }
                Spacer()
                Button("Save") { save() }
                    .buttonStyle(SquareButtonStyle())
                    .disabled(!canSave)
                    .keyboardShortcut(.defaultAction)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(EdgeInsets(top: 26, leading: 20, bottom: 20, trailing: 20))
        .foregroundStyle(Pane.text)
    }

    /// A modal card styled like this window (Pane chrome, sharp edges, square
    /// buttons) confirming deletion. Cancel / red Delete.
    private var deleteConfirmation: some View {
        ZStack {
            Color.black.opacity(0.45)
                .contentShape(Rectangle())
                .onTapGesture { showDeleteConfirm = false }
            VStack(alignment: .leading, spacing: 16) {
                Text("Delete “\(draft.name)”?")
                    .font(.system(size: 13, weight: .semibold))
                Text("This permanently removes the custom theme and can’t be undone.")
                    .font(.system(size: 11))
                    .foregroundStyle(Pane.muted)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Button("Cancel") { showDeleteConfirm = false }
                        .buttonStyle(SquareButtonStyle())
                    Spacer()
                    Button("Delete") { performDelete() }
                        .buttonStyle(SquareButtonStyle(tint: Self.deleteRed))
                }
            }
            .padding(20)
            .frame(width: 260)
            .background(Pane.window)
            .overlay(Rectangle().strokeBorder(Pane.border, lineWidth: 1))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(Pane.text)
    }

    // MARK: - Actions

    /// Remove the saved custom and close. The Appearance window repoints its
    /// selection via its `onChange(of: customsData)` if it was showing this one.
    private func performDelete() {
        if let id = draft.editingId {
            var all = ThemeSettings.decodeCustoms(customsData)
            all.removeAll { $0.id == id }
            customsData = ThemeSettings.encodeCustoms(all)
        }
        showDeleteConfirm = false
        dismiss()
    }

    /// Persist the palette into the theme library and select it back in the
    /// Appearance window (via `savedId`), then close. The Custom builder only
    /// DEFINES a palette; choosing it and applying it to the document happens in
    /// the Appearance window, like any preset. `onDisappear` dismisses the color
    /// picker and returns focus to the Appearance window.
    private func save() {
        let id = persistPalette()
        draft.savedId = id
        dismiss()
    }

    /// Write the draft into the saved customs (insert or update) and return its id.
    @discardableResult
    private func persistPalette() -> String {
        let slots = (0..<draft.slotCount).map { i in
            ColorPair(light: CustomDraft.hex(draft.lights[i]), dark: CustomDraft.hex(draft.darks[i]))
        }
        let id = draft.editingId ?? "custom.\(UUID().uuidString)"
        let palette = Palette(id: id, name: draft.name.trimmingCharacters(in: .whitespaces),
                              scheme: draft.scheme, slots: slots)
        var all = ThemeSettings.decodeCustoms(customsData)
        if let idx = all.firstIndex(where: { $0.id == id }) { all[idx] = palette } else { all.append(palette) }
        customsData = ThemeSettings.encodeCustoms(all)
        draft.editingId = id
        return id
    }
}

/// A sharp, square color well. SwiftUI's `ColorPicker` always draws a rounded
/// system swatch, and the prior approach hid it under a near-zero SwiftUI
/// `.opacity`, which drops the control out of SwiftUI hit-testing, so clicks
/// fell through to the square behind it and the panel never opened. Instead we
/// draw the square ourselves and overlay a real `NSColorWell`: AppKit hit-testing
/// ignores a view's `alphaValue`, so the well stays clickable while invisible,
/// and AppKit handles opening the shared color panel, exclusive activation, and
/// reporting the chosen color.
struct SquareColorWell: View {
    @Binding var color: Color
    var size: CGFloat = 24
    /// Draws the selection ring when this is the active (panel-target) swatch.
    var isSelected: Bool = false
    /// Called when this well becomes the active color-panel target (on click).
    var onActivate: () -> Void = {}

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(width: size, height: size)
            // Quiet hairline on every swatch, always.
            .overlay(Rectangle().strokeBorder(Color(white: 0.47).opacity(0.5), lineWidth: 1))
            // Selection ring: OUTSET so it sits just outside the swatch against the
            // window background, which `labelColor` always contrasts with. A ring
            // drawn ON the swatch would vanish when the swatch is near label color
            // (e.g. a white dark-swatch in Dark mode). Neutral, no accent.
            .overlay(
                Rectangle()
                    .strokeBorder(Color(nsColor: .labelColor), lineWidth: 2)
                    .padding(-3)
                    .opacity(isSelected ? 1 : 0)
            )
            .overlay(ColorWellBridge(color: $color, onActivate: onActivate))
    }
}

/// An invisible AppKit `NSColorWell` layered over `SquareColorWell`'s square,
/// bridging the chosen color to a SwiftUI binding. Used in place of `ColorPicker`
/// so the visible control can be a true square and stay reliably clickable.
private struct ColorWellBridge: NSViewRepresentable {
    @Binding var color: Color
    /// Surfaced from `PanelColorWell.activate` so SwiftUI learns which swatch is
    /// the active panel target and can draw its selection ring.
    var onActivate: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator(color: $color) }

    func makeNSView(context: Context) -> NSColorWell {
        let well = PanelColorWell()
        well.alphaValue = 0.02            // invisible, but AppKit still hit-tests it
        well.color = NSColor(color)
        well.target = context.coordinator
        well.action = #selector(Coordinator.colorChanged(_:))
        well.onActivate = onActivate
        return well
    }

    func updateNSView(_ well: NSColorWell, context: Context) {
        context.coordinator.color = $color
        (well as? PanelColorWell)?.onActivate = onActivate
        // Reflect external binding changes (e.g. loading a saved palette) without
        // re-firing the action, a programmatic `color` set doesn't trigger it.
        let ns = NSColor(color)
        if well.color.hexString != ns.hexString { well.color = ns }
    }

    @MainActor final class Coordinator: NSObject {
        var color: Binding<Color>
        init(color: Binding<Color>) { self.color = color }
        @objc func colorChanged(_ sender: NSColorWell) {
            // Force opaque: custom theme colors persist as opaque hex, so a
            // translucent pick would make the live preview (which keeps alpha)
            // disagree with what's actually saved. Pin alpha to 1 at the source.
            color.wrappedValue = Color(nsColor: sender.color.withAlphaComponent(1))
        }
    }
}

/// An `NSColorWell` that hides the shared panel's opacity slider (custom theme
/// colors persist as opaque hex) and activates exclusively, so only one well
/// drives the panel at a time. `showsAlpha` is set after `super.activate`, since
/// activation configures the shared panel.
private final class PanelColorWell: NSColorWell {
    var onActivate: () -> Void = {}
    override func activate(_ exclusive: Bool) {
        super.activate(true)            // exclusive: only one well is the panel target
        NSColorPanel.shared.showsAlpha = false
        // The Custom Theme window floats above the document; float the shared color
        // panel to the same level so it still comes forward over the window when
        // picking a color (otherwise the floating window would trap it behind).
        NSColorPanel.shared.level = .floating
        onActivate()                    // tell SwiftUI which swatch is now selected
    }
}

/// Positions the Custom Theme window (once) just left of the Appearance window,
/// so that window's live preview stays visible while editing. (Both windows pin
/// their appearance to the OS via `SystemWindowAppearance`, matching the system
/// color picker.)
struct PositionBesideAppearance: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { NSView() }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard !context.coordinator.positioned else { return }
        DispatchQueue.main.async {
            guard let w = nsView.window else { return }
            context.coordinator.positioned = true
            let visible = (w.screen ?? NSScreen.main)?.visibleFrame
            if let appWin = NSApp.windows.first(where: { $0.title == "Appearance" && $0 !== w }) {
                let f = appWin.frame
                // Prefer just-left of the Appearance window so its live preview
                // stays visible; if that would run off the left edge, place it
                // just-right instead.
                var topLeft = NSPoint(x: f.minX - w.frame.width - 14, y: f.maxY)
                if let visible, topLeft.x < visible.minX {
                    topLeft = NSPoint(x: f.maxX + 14, y: f.maxY)
                }
                w.setFrameTopLeftPoint(topLeft)
            }
            // Final safety: pull fully on screen however it ended up placed.
            if let visible {
                let fixed = WindowPlacement.onScreen(w.frame, in: visible)
                if fixed != w.frame { w.setFrame(fixed, display: true) }
            }
        }
    }

    final class Coordinator { var positioned = false }
}

/// Raises and keys the Custom Theme window once, when it appears, so it takes
/// focus over the document window it was opened over. The window is also pinned
/// above the document by `FloatAboveDocument`; the shared color panel is floated
/// to match (see PanelColorWell.activate) so color picking still works.
struct RaiseOnOpen: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { NSView() }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard !context.coordinator.raised else { return }
        DispatchQueue.main.async {
            guard let w = nsView.window else { return }
            context.coordinator.raised = true
            w.makeKeyAndOrderFront(nil)
        }
    }

    final class Coordinator { var raised = false }
}
