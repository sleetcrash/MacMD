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
    /// Set to the id just saved, so the Appearance window can select it.
    @Published var savedId: String?

    var slotCount: Int { scheme == .standard ? 3 : 1 }

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
/// Appearance window (same neutral gray, sharp edges, square buttons). It has no
/// preview of its own; editing colors live-updates the Appearance window's
/// preview through the shared `CustomDraft`.
struct CustomThemeEditor: View {
    @EnvironmentObject private var draft: CustomDraft
    @AppStorage(ThemeSettings.customsKey) private var customsData = Data()
    @Environment(\.dismiss) private var dismiss

    private var slotLabels: [String] { draft.scheme == .standard ? ["H1", "H2", "H3"] : ["Color"] }
    private var saved: [Palette] {
        ThemeSettings.decodeCustoms(customsData).filter { $0.scheme == draft.scheme }
    }
    private var canSave: Bool { !draft.name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(draft.editingId == nil ? "New \(draft.scheme.displayName) Theme" : "Edit Theme")
                .font(.system(size: 12, weight: .semibold))

            Text("Select a swatch, then use the color picker to choose its color.")
                .font(.system(size: 10))
                .foregroundStyle(Pane.muted)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text("").frame(width: 36)
                    ForEach(0..<draft.slotCount, id: \.self) { i in
                        Text(slotLabels[i]).font(.system(size: 11)).foregroundStyle(Pane.muted)
                    }
                }
                GridRow {
                    Text("Light").font(.system(size: 11)).frame(width: 36, alignment: .leading)
                    ForEach(0..<draft.slotCount, id: \.self) { i in
                        ColorPicker("", selection: $draft.lights[i], supportsOpacity: false)
                            .labelsHidden()
                            .clipShape(Rectangle())
                    }
                }
                GridRow {
                    Text("Dark").font(.system(size: 11)).frame(width: 36, alignment: .leading)
                    ForEach(0..<draft.slotCount, id: \.self) { i in
                        ColorPicker("", selection: $draft.darks[i], supportsOpacity: false)
                            .labelsHidden()
                            .clipShape(Rectangle())
                    }
                }
            }

            HStack(spacing: 10) {
                TextField("Name", text: $draft.name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .padding(.horizontal, 8)
                    .frame(width: 150, height: 26)
                    .background(Pane.field)
                    .overlay(Rectangle().strokeBorder(Pane.border, lineWidth: 1))
                    .onChange(of: draft.name) { _, v in if v.count > 10 { draft.name = String(v.prefix(10)) } }
                Button(draft.editingId == nil ? "Save" : "Update") { save() }
                    .buttonStyle(SquareButtonStyle())
                    .disabled(!canSave)
                if draft.editingId != nil {
                    Button("New") { resetFields() }.buttonStyle(SquareButtonStyle())
                }
                Spacer()
            }

            if !saved.isEmpty {
                Rectangle().fill(Pane.border).frame(height: 1)
                Text("SAVED").font(.system(size: 9)).tracking(0.6).foregroundStyle(Pane.muted)
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(saved) { p in
                            HStack(spacing: 8) {
                                Button { load(p) } label: {
                                    HStack(spacing: 4) {
                                        ForEach(Array(p.slots.enumerated()), id: \.offset) { _, slot in
                                            Swatch(color: Color(nsColor: slot.nsLight))
                                        }
                                        Text(p.name).font(.system(size: 11))
                                    }
                                }
                                .buttonStyle(.plain)
                                Spacer()
                                Button { delete(p) } label: {
                                    Image(systemName: "trash").font(.system(size: 11))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .frame(maxHeight: 120)
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(SquareButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(EdgeInsets(top: 26, leading: 20, bottom: 20, trailing: 20))
        .frame(width: 320)
        .foregroundStyle(Pane.text)
        .background(Pane.window)
        .background(SystemWindowAppearance())
        .background(PositionBesideAppearance())
        .onDisappear { draft.end() }
    }

    // MARK: - Actions

    private func save() {
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
        draft.savedId = id
    }

    private func load(_ p: Palette) {
        draft.name = p.name
        draft.editingId = p.id
        draft.lights = p.slots.map { Color(nsColor: $0.nsLight) }
        draft.darks = p.slots.map { Color(nsColor: $0.nsDark) }
    }

    private func delete(_ p: Palette) {
        var all = ThemeSettings.decodeCustoms(customsData)
        all.removeAll { $0.id == p.id }
        customsData = ThemeSettings.encodeCustoms(all)
        if draft.editingId == p.id { resetFields() }
    }

    private func resetFields() {
        draft.name = ""
        draft.editingId = nil
        draft.lights = Array(repeating: .black, count: draft.slotCount)
        draft.darks = Array(repeating: .white, count: draft.slotCount)
    }
}

/// Positions the Custom Theme window (once) just left of the Appearance window,
/// so that window's live preview stays visible while editing. (Appearance is set
/// by `.preferredColorScheme(.dark)`, matching the system color picker.)
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
