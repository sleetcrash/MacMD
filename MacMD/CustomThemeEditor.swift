import SwiftUI
import AppKit

/// The single surface for all custom-theme management. Light + dark color wells
/// per slot (1 slot Unified, 3 slots Standard), a name (≤10 chars), Save, and
/// the saved list with a trash control + load-to-edit. Persists to the same
/// `customPalettes` UserDefaults blob the dropdown reads.
struct CustomThemeEditor: View {
    let coloring: Coloring
    @Binding var customsData: Data
    @Binding var selectedThemeId: String
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var editingId: String?
    @State private var lights: [Color]
    @State private var darks: [Color]

    init(coloring: Coloring, customsData: Binding<Data>, selectedThemeId: Binding<String>) {
        self.coloring = coloring
        self._customsData = customsData
        self._selectedThemeId = selectedThemeId
        let count = coloring == .standard ? 3 : 1
        _lights = State(initialValue: Array(repeating: Color.gray, count: count))
        _darks = State(initialValue: Array(repeating: Color.gray, count: count))
    }

    private var slotCount: Int { coloring == .standard ? 3 : 1 }
    private var slotLabels: [String] { coloring == .standard ? ["H1", "H2", "H3"] : ["Color"] }
    private var saved: [Palette] {
        ThemeSettings.decodeCustoms(customsData).filter { $0.scheme == coloring }
    }
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(editingId == nil ? "New \(coloring.displayName) Theme" : "Edit Theme")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text("").frame(width: 28)
                    ForEach(0..<slotCount, id: \.self) { i in
                        Text(slotLabels[i]).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                GridRow {
                    Text("Light").font(.system(size: 11)).frame(width: 36, alignment: .leading)
                    ForEach(0..<slotCount, id: \.self) { i in
                        ColorPicker("", selection: $lights[i], supportsOpacity: false).labelsHidden()
                    }
                }
                GridRow {
                    Text("Dark").font(.system(size: 11)).frame(width: 36, alignment: .leading)
                    ForEach(0..<slotCount, id: \.self) { i in
                        ColorPicker("", selection: $darks[i], supportsOpacity: false).labelsHidden()
                    }
                }
            }

            HStack {
                TextField("Name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
                    .onChange(of: name) { _, newValue in
                        if newValue.count > 10 { name = String(newValue.prefix(10)) }
                    }
                Button(editingId == nil ? "Save" : "Update") { save() }
                    .disabled(!canSave)
                if editingId != nil {
                    Button("New") { resetFields() }
                }
            }

            if !saved.isEmpty {
                Divider()
                Text("Saved").font(.system(size: 11)).foregroundStyle(.secondary)
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(saved) { p in
                            HStack {
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
                                Button(role: .destructive) { delete(p) } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }
                .frame(maxHeight: 160)
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 340)
    }

    // MARK: - Actions

    private func save() {
        let slots = (0..<slotCount).map { i in
            ColorPair(light: hex(from: lights[i]), dark: hex(from: darks[i]))
        }
        let id = editingId ?? "custom.\(UUID().uuidString)"
        let palette = Palette(id: id, name: name.trimmingCharacters(in: .whitespaces),
                              scheme: coloring, slots: slots)
        var all = ThemeSettings.decodeCustoms(customsData)
        if let idx = all.firstIndex(where: { $0.id == id }) {
            all[idx] = palette
        } else {
            all.append(palette)
        }
        customsData = ThemeSettings.encodeCustoms(all)
        selectedThemeId = id
        editingId = id
    }

    private func load(_ p: Palette) {
        name = p.name
        editingId = p.id
        lights = p.slots.map { Color(nsColor: $0.nsLight) }
        darks = p.slots.map { Color(nsColor: $0.nsDark) }
    }

    private func delete(_ p: Palette) {
        var all = ThemeSettings.decodeCustoms(customsData)
        all.removeAll { $0.id == p.id }
        customsData = ThemeSettings.encodeCustoms(all)
        if selectedThemeId == p.id {
            selectedThemeId = coloring == .standard ? ColorTheming.defaultStandardId : ColorTheming.defaultUnifiedId
        }
        if editingId == p.id { resetFields() }
    }

    private func resetFields() {
        name = ""
        editingId = nil
        lights = Array(repeating: .gray, count: slotCount)
        darks = Array(repeating: .gray, count: slotCount)
    }

    private func hex(from color: Color) -> String {
        let ns = NSColor(color)
        return (ns.usingColorSpace(.sRGB) ?? ns).hexString
    }
}
