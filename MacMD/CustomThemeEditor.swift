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
    @Published var lights: [Color] = [.black]
    @Published var darks: [Color] = [.white]
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

    // Grid geometry. The Name field's right edge lines up with the last swatch
    // by matching the grid's measured width (`gridWidth`); `rowWidth` is only the
    // pre-measurement fallback.
    private let labelCol: CGFloat = 36
    private let wellSize: CGFloat = 24
    private let hSpacing: CGFloat = 12
    private var rowWidth: CGFloat { labelCol + CGFloat(draft.slotCount) * (hSpacing + wellSize) }
    @State private var gridWidth: CGFloat = 0

    private var slotLabels: [String] { draft.scheme == .standard ? ["H1", "H2", "H3"] : ["Color"] }
    private var canSave: Bool { !draft.name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(draft.editingId == nil ? "New Custom Theme" : "Edit Custom Theme")
                .font(.system(size: 12, weight: .semibold))

            Text("Select a swatch, then use the color picker to customize your theme. View the Preview pane to see your changes. Name your theme and save.")
                .font(.system(size: 10))
                .foregroundStyle(Pane.muted)
                .fixedSize(horizontal: false, vertical: true)

            Grid(alignment: .leading, horizontalSpacing: hSpacing, verticalSpacing: 8) {
                GridRow {
                    Text("").frame(width: labelCol)
                    ForEach(0..<draft.slotCount, id: \.self) { i in
                        Text(slotLabels[i]).font(.system(size: 11)).foregroundStyle(Pane.muted)
                            .frame(width: wellSize, alignment: .center)
                    }
                }
                GridRow {
                    Text("Light").font(.system(size: 11)).frame(width: labelCol, alignment: .leading)
                    ForEach(0..<draft.slotCount, id: \.self) { i in
                        SquareColorWell(color: $draft.lights[i], size: wellSize)
                            .accessibilityLabel("\(slotLabels[i]) light color")
                    }
                }
                GridRow {
                    Text("Dark").font(.system(size: 11)).frame(width: labelCol, alignment: .leading)
                    ForEach(0..<draft.slotCount, id: \.self) { i in
                        SquareColorWell(color: $draft.darks[i], size: wellSize)
                            .accessibilityLabel("\(slotLabels[i]) dark color")
                    }
                }
            }
            .background(GeometryReader { geo in
                Color.clear.preference(key: GridWidthKey.self, value: geo.size.width)
            })
            .onPreferenceChange(GridWidthKey.self) { gridWidth = $0 }

            // Name box ends in line with the rightmost swatch (the grid's width).
            TextField("Name", text: $draft.name)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .padding(.horizontal, 8)
                .frame(width: gridWidth > 0 ? gridWidth : rowWidth, height: 26)
                .background(Pane.field)
                .overlay(Rectangle().strokeBorder(Pane.border, lineWidth: 1))
                .onChange(of: draft.name) { _, v in if v.count > 10 { draft.name = String(v.prefix(10)) } }

            // Close (left) / Apply / Save (right) — matches the Appearance window.
            HStack(spacing: 10) {
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
        .frame(width: 320)
        .foregroundStyle(Pane.text)
        .background(Pane.window)
        .background(SystemWindowAppearance())
        .background(PositionBesideAppearance())
        .onExitCommand { dismiss() }
        .onDisappear {
            draft.end()
            // Close the color picker and hand focus back to the Appearance
            // window (not the document) however this window was dismissed.
            NSColorPanel.shared.orderOut(nil)
            NSApp.windows.first { $0.title == "Appearance" }?.makeKeyAndOrderFront(nil)
        }
    }

    // MARK: - Actions

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

/// Publishes the swatch grid's measured width so the Name field can match it
/// exactly (its right edge then lines up with the last swatch).
private struct GridWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
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
