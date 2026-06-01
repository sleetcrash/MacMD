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
        active = true
    }

    func end() { active = false }

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

/// The Custom Theme editor — a separate window styled as an extension of the
/// Appearance window (same neutral chrome, sharp edges, square buttons). It has
/// no preview of its own; editing colors live-updates the Appearance window's
/// preview through the shared `CustomDraft`. Apply pushes the theme to the live
/// document (transient, like the Appearance window's Apply); Save commits it and
/// closes; Close (or the red X) returns to the Appearance window.
struct CustomThemeEditor: View {
    @EnvironmentObject private var draft: CustomDraft
    @EnvironmentObject private var theme: ThemeController
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
        .frame(width: 354)   // matches the Appearance window; fits Delete/Close/Apply/Save
        .background(Pane.window)
        .background(SystemWindowAppearance())
        .background(PositionBesideAppearance())
        .onExitCommand {
            if showDeleteConfirm { showDeleteConfirm = false } else { dismiss() }
        }
        .onDisappear {
            draft.end()
            // Close the color picker and hand focus back to the Appearance
            // window (not the document) however this window was dismissed.
            NSColorPanel.shared.orderOut(nil)
            NSApp.windows.first { $0.title == "Appearance" }?.makeKeyAndOrderFront(nil)
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(draft.editingId == nil ? "New Custom Theme" : "Edit Custom Theme")
                .font(.system(size: 12, weight: .semibold))

            Text("Select a swatch, then use the color picker to customize your theme. View the Preview pane to see your changes. Name your theme and save.")
                .font(.system(size: 10))
                .foregroundStyle(Pane.muted)
                .fixedSize(horizontal: false, vertical: true)

            // One swatch row laid out like the Appearance theme box: light trio │
            // dark trio, with a sun (left) and moon (right) marking which is which.
            // Heading labels sit centered above each swatch; the Name box spans the
            // swatch columns, lining up with the first and last swatch.
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
                        SquareColorWell(color: $draft.lights[i], size: wellSize)
                            .accessibilityLabel("\(slotLabels[i]) light color")
                    }
                    Text("|").opacity(0.35)
                    ForEach(0..<safeCount, id: \.self) { i in
                        SquareColorWell(color: $draft.darks[i], size: wellSize)
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
                        .gridCellColumns(safeCount * 2 + 1)   // L1 … D3 (the swatches)
                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])   // moon column
                }
            }

            // Delete (red, only when editing a saved theme) / Close on the left;
            // Apply / Save on the right — matches the Appearance window.
            HStack(spacing: 10) {
                if draft.editingId != nil {
                    Button("Delete") { showDeleteConfirm = true }
                        .buttonStyle(SquareButtonStyle(tint: Self.deleteRed))
                }
                Button("Close") { dismiss() }
                    .buttonStyle(SquareButtonStyle())
                Spacer()
                Button("Apply") { apply() }
                    .buttonStyle(SquareButtonStyle())
                    .disabled(!canSave)
                Button("Save") { save() }
                    .buttonStyle(SquareButtonStyle())
                    .disabled(!canSave)
                    .keyboardShortcut(.defaultAction)
            }
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

    /// Apply the custom theme to the live document and keep editing — transient,
    /// exactly like the Appearance window's Apply. Persists the palette so it is
    /// resolvable and appears in the dropdown.
    private func apply() {
        let id = persistPalette()
        theme.apply(coloring: draft.scheme, themeId: id,
                    fontSize: theme.fontSize, appearance: theme.appearance)
        draft.savedId = id
    }

    /// Persist the selection, apply it, and close. `onDisappear` then dismisses
    /// the color picker and returns focus to the Appearance window.
    private func save() {
        let id = persistPalette()
        theme.save(coloring: draft.scheme, themeId: id,
                   fontSize: theme.fontSize, appearance: theme.appearance)
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

/// A sharp-edged square color well that matches the dropdown swatches: a flat
/// color square with a nearly-invisible system `ColorPicker` layered on top to
/// open the color panel on click and write the binding. (`ColorPicker` on its
/// own renders a rounded well that `.clipShape(Rectangle())` does not fully
/// square on macOS, so the visible square is drawn separately.)
struct SquareColorWell: View {
    @Binding var color: Color
    var size: CGFloat = 24

    var body: some View {
        ZStack {
            Rectangle().fill(color)
            ColorPicker("", selection: $color, supportsOpacity: false)
                .labelsHidden()
                .scaleEffect(1.4)   // enlarge the hit area to cover the square
                .opacity(0.02)      // keep it interactive but visually absent
        }
        .frame(width: size, height: size)
        .clipShape(Rectangle())
        .overlay(Rectangle().strokeBorder(Color(white: 0.47).opacity(0.5), lineWidth: 1))
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
            if let appWin = NSApp.windows.first(where: { $0.title == "Appearance" && $0 !== w }) {
                let f = appWin.frame
                w.setFrameTopLeftPoint(NSPoint(x: f.minX - w.frame.width - 14, y: f.maxY))
            }
        }
    }

    final class Coordinator { var positioned = false }
}
