import SwiftUI
import AppKit

/// Identifies the Theme Builder window, opened from the Theme dropdown’s Customize row.
enum CustomThemeScene {
    static let id = "customTheme"
}

/// Shared, observable draft of the custom theme being edited. Lives in the app
/// and is injected into both the Settings window and the Theme Builder window,
/// so editing colors here drives the Settings window's live preview.
@MainActor
final class CustomDraft: ObservableObject {
    @Published var active = false
    @Published var scheme: Coloring = .unified
    @Published var kind: Kind = .dynamic
    @Published var name = ""
    @Published var editingId: String?
    // The heading slots as two editable columns. A static theme edits only the
    // light column; `buildPalette` collapses it to identical pairs. Default to
    // the unified scheme's single slot so the initial state is self-consistent
    // (scheme → slotCount → array counts) before begin/beginEditing.
    @Published var lights: [Color] = [.black]
    @Published var darks: [Color] = [.white]
    /// The two background wells (dynamic uses both; static edits the light one).
    @Published var bgLight = BackgroundWell(hex: EditorBackground.defaultPair.light, fromPanel: false)
    @Published var bgDark = BackgroundWell(hex: EditorBackground.defaultPair.dark, fromPanel: false)
    /// Set to the id just saved/applied, so the Settings window can select it.
    @Published var savedId: String?
    /// (side, slot) of the heading swatch whose color well is the active panel
    /// target, so only that swatch draws a selection ring. nil = nothing selected.
    @Published var selectedWell: SelectedWell?

    enum Side: Equatable { case light, dark }
    struct SelectedWell: Equatable { var side: Side; var slot: Int }

    /// Whether the theme is one fixed look (static, identical light/dark pairs) or
    /// a light/dark pair that follows the Mode (dynamic).
    enum Kind: Equatable {
        case `static`, dynamic
        var displayName: String { self == .static ? "Static" : "Dynamic" }
    }

    /// A background color well: its current hex plus whether that value was last
    /// set from the color panel. Save adds panel-sourced backgrounds to the
    /// library; quick-picks clear the flag so they never auto-add.
    struct BackgroundWell: Equatable {
        var hex: String
        var fromPanel: Bool
    }

    static func slotCount(for scheme: Coloring) -> Int {
        switch scheme {
        case .off: return 0
        case .unified: return 1
        case .standard: return 3
        }
    }
    var slotCount: Int { Self.slotCount(for: scheme) }

    /// Start a brand-new custom theme (Dynamic, Unified, default background).
    func begin(scheme: Coloring) {
        self.scheme = scheme
        kind = .dynamic
        name = ""
        editingId = nil
        let count = Self.slotCount(for: scheme)
        // Black (light) / white (dark) so the preview shows the default look until
        // a swatch is given a color.
        lights = Array(repeating: .black, count: count)
        darks = Array(repeating: .white, count: count)
        bgLight = BackgroundWell(hex: EditorBackground.defaultPair.light, fromPanel: false)
        bgDark = BackgroundWell(hex: EditorBackground.defaultPair.dark, fromPanel: false)
        savedId = nil
        selectedWell = nil
        active = true
    }

    /// Load an existing saved custom palette back into the editor (the pencil
    /// affordance on a custom dropdown row).
    func beginEditing(_ palette: Palette) {
        scheme = palette.scheme
        kind = palette.isStatic ? .static : .dynamic
        name = palette.name
        editingId = palette.id
        // Normalize to the scheme's slot count (padding with the begin() defaults
        // or truncating) so a malformed stored palette whose slot count disagrees
        // with its scheme can't run the slot-indexed reads off the end.
        let count = Self.slotCount(for: palette.scheme)
        lights = Self.fit(palette.slots.map { Color(nsColor: $0.nsLight) }, to: count, pad: .black)
        darks = Self.fit(palette.slots.map { Color(nsColor: $0.nsDark) }, to: count, pad: .white)
        // The stored background was chosen but did not come from THIS session's
        // panel, so re-saving without touching it must not re-add it.
        bgLight = BackgroundWell(hex: palette.background.light, fromPanel: false)
        bgDark = BackgroundWell(hex: palette.background.dark, fromPanel: false)
        savedId = nil
        selectedWell = nil
        active = true
    }

    /// Pad (with `pad`) or truncate `colors` to exactly `count` slots.
    private static func fit(_ colors: [Color], to count: Int, pad: Color) -> [Color] {
        if colors.count > count { return Array(colors.prefix(count)) }
        if colors.count < count { return colors + Array(repeating: pad, count: count - colors.count) }
        return colors
    }

    func end() { active = false; selectedWell = nil }

    /// Switch the heading scheme, clearing the active well selection. A non-None
    /// scheme reshapes the visible grid via pad/truncate (padding new slots with
    /// the black/white prefill); None hides the grid but keeps the in-memory slots
    /// so switching back re-shows them.
    func changeScheme(_ new: Coloring) {
        guard new != scheme else { return }
        scheme = new
        selectedWell = nil
        guard new != .off else { return }
        lights = Self.fit(lights, to: slotCount, pad: .black)
        darks = Self.fit(darks, to: slotCount, pad: .white)
    }

    /// Switch the kind, clearing the active well selection. Dynamic to static
    /// collapses to the light column's values and provenance; static to dynamic
    /// leaves both columns (already equal) for independent editing.
    func changeKind(_ new: Kind) {
        guard new != kind else { return }
        kind = new
        selectedWell = nil
        if new == .static {
            darks = lights
            bgDark = bgLight
        }
    }

    /// Apply a light/dark background pair to both wells (a dynamic quick-pick),
    /// clearing panel provenance so it never auto-adds to the library.
    func applyPairBackground(_ pair: ColorPair) {
        bgLight = BackgroundWell(hex: pair.light, fromPanel: false)
        bgDark = BackgroundWell(hex: pair.dark, fromPanel: false)
        selectedWell = nil
    }

    /// Apply a single background color (a static quick-pick or a saved swatch),
    /// clearing panel provenance. Static mirrors it across both wells so a later
    /// switch to dynamic seeds both columns; dynamic fills the light well.
    func applySingleBackground(_ hex: String) {
        let well = BackgroundWell(hex: hex, fromPanel: false)
        bgLight = well
        if kind == .static { bgDark = well }
        selectedWell = nil
    }

    var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    /// The background pair, collapsed to an identical pair when static.
    var backgroundPair: ColorPair {
        kind == .static ? ColorPair(light: bgLight.hex, dark: bgLight.hex)
                        : ColorPair(light: bgLight.hex, dark: bgDark.hex)
    }

    /// The active scheme's slots, collapsed to identical pairs when static. None
    /// yields zero slots regardless of any retained in-memory columns.
    private var builtSlots: [ColorPair] {
        let n = min(slotCount, lights.count, darks.count)
        guard n > 0 else { return [] }
        return (0..<n).map { i in
            let l = CustomDraft.hex(lights[i])
            return ColorPair(light: l, dark: kind == .static ? l : CustomDraft.hex(darks[i]))
        }
    }

    /// The in-progress palette for the Settings window's preview (stable id so
    /// SwiftUI identity doesn't churn on each edit).
    var palette: Palette {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return Palette(id: editingId ?? "draft.custom",
                       name: trimmed.isEmpty ? "Custom" : trimmed,
                       scheme: scheme, slots: builtSlots,
                       background: backgroundPair, isStatic: kind == .static)
    }

    /// The palette to persist: scheme-correct slot count (0, 1, or 3), identical
    /// pairs when static, background from the wells.
    func buildPalette() -> Palette {
        Palette(id: editingId ?? "custom.\(UUID().uuidString)",
                name: name.trimmingCharacters(in: .whitespaces),
                scheme: scheme, slots: builtSlots,
                background: backgroundPair, isStatic: kind == .static)
    }

    /// The background hexes owed to the library on Save: each well whose current
    /// value was last set from the color panel (both wells for dynamic; the
    /// single collapsed value for static). Last-writer-per-well provenance.
    func panelPickedBackgrounds() -> [String] {
        if kind == .static { return bgLight.fromPanel ? [bgLight.hex] : [] }
        return [bgLight, bgDark].filter(\.fromPanel).map(\.hex)
    }

    static func hex(_ color: Color) -> String {
        let ns = NSColor(color)
        return (ns.usingColorSpace(.sRGB) ?? ns).hexString
    }
}

/// The Theme Builder, a separate window styled as an extension of the
/// Settings window (same neutral chrome, sharp edges, square buttons). It has
/// no preview of its own; editing colors live-updates the Settings window's
/// preview through the shared `CustomDraft`. Save commits the palette to the
/// theme library and selects it in the Settings window (apply it to the
/// document from there, like any preset); Close (or the red X) returns to the
/// Settings window.
struct CustomThemeEditor: View {
    @EnvironmentObject private var draft: CustomDraft
    @AppStorage(ThemeSettings.customThemesKey) private var customsData = Data()
    @Environment(\.dismiss) private var dismiss

    private let wellSize: CGFloat = 24
    @State private var showDeleteConfirm = false
    /// Re-read the saved-background library after a remove so the row updates.
    @State private var libraryTick = 0
    static let deleteRed = Color(red: 0.80, green: 0.25, blue: 0.27)
    /// One width for every action button (Delete / Save / Cancel) so a row of them
    /// is uniform across the editor and the confirmation. The explicit width also
    /// keeps the confirmation's buttons drawing as the square SquareButtonStyle:
    /// without it the system fell back to a default rounded bezel for an
    /// intrinsically-sized custom button on that pure-SwiftUI page.
    static let actionWidth: CGFloat = 96

    private var slotLabels: [String] { draft.scheme == .standard ? ["H1", "H2", "H3"] : ["Color"] }
    // The slot count that is safe to index across every per-slot array, guarding
    // renders during a scheme change (or any momentarily inconsistent state).
    private var safeCount: Int { min(draft.lights.count, draft.darks.count, slotLabels.count) }

    private var savedBackgrounds: [String] {
        _ = libraryTick
        return BackgroundLibrary.all()
    }

    var body: some View {
        // The confirmation REPLACES the editor as the window's content instead of
        // floating over it as a dimmed overlay. The window is
        // `.windowResizability(.contentSize)`, so it simply resizes to whichever
        // page is shown. The previous dimmed card needed a greedy full-bleed
        // backdrop which, in a content-sized window, didn't cover cleanly and left
        // a black band above the card; a plain sibling page has no backdrop to
        // misfit. (The square button rendering is handled by `actionWidth`.)
        Group {
            if showDeleteConfirm {
                deleteConfirmation
            } else {
                editor
            }
        }
            .frame(width: 264)   // hugs the swatch row; no Close button to widen for
            .background(Pane.window)
            .background(SystemWindowAppearance())
            .background(PositionBesideSettings())
            .background(RaiseOnOpen())
            .background(FloatAboveDocument())
            .onExitCommand {
                if showDeleteConfirm { showDeleteConfirm = false } else { dismiss() }
            }
            .onDisappear {
                // Reset the confirmation so closing this window (red dot) while it is
                // showing doesn't reopen straight into the confirmation next time the
                // same theme is edited. The window is a singleton scene whose state
                // otherwise persists across close/reopen.
                showDeleteConfirm = false
                draft.end()
                // Close the color picker and hand focus back to the Settings window
                // (not the document) however this window was dismissed, but only if
                // Settings is still on screen. When Settings is the one closing (it
                // cascades this window shut), re-showing it here would resurrect a
                // closing window, so skip the re-focus in that case.
                NSColorPanel.shared.orderOut(nil)
                NSColorPanel.shared.level = .normal   // undo the floating level set while picking
                if let appWin = NSApp.windows.first(where: { $0.title == "Settings" }), appWin.isVisible {
                    appWin.makeKeyAndOrderFront(nil)
                }
            }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Theme Builder")
                .font(.system(size: 12, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .center)

            // Static or dynamic, then the heading scheme (None / Unified / Standard).
            kindControl
            schemeControl

            // The heading swatch grid: two columns (light │ dark) when dynamic, a
            // single column when static, absent under None. The background wells,
            // quick-picks, and saved library follow, then the Name field and the
            // Save / Delete actions.
            headingSection
            backgroundSection
            nameField

            // Save sits bottom-right and Delete (red outline, only when editing a
            // saved theme) bottom-left, at the window margins -- the macOS-standard
            // action placement. The title-bar close button dismisses the window, so
            // there is no separate Close button to duplicate it.
            HStack(spacing: 10) {
                if draft.editingId != nil {
                    Button("Delete") { showDeleteConfirm = true }
                        .buttonStyle(SquareButtonStyle(outline: Self.deleteRed, width: Self.actionWidth))
                }
                Spacer()
                Button("Save") { save() }
                    .buttonStyle(SquareButtonStyle(width: Self.actionWidth))
                    .disabled(!draft.canSave)
                    .keyboardShortcut(.defaultAction)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(EdgeInsets(top: 26, leading: 20, bottom: 20, trailing: 20))
        .foregroundStyle(Pane.text)
    }

    // MARK: - Segments

    /// Static | Dynamic, in the settings-window segment style.
    private var kindControl: some View {
        HStack(spacing: 0) {
            segment(title: CustomDraft.Kind.static.displayName, selected: draft.kind == .static) {
                draft.changeKind(.static)
            }
            segment(title: CustomDraft.Kind.dynamic.displayName, selected: draft.kind == .dynamic) {
                draft.changeKind(.dynamic)
            }
        }
        .frame(height: 24)
        .background(Pane.field)
        .overlay(Rectangle().strokeBorder(Pane.border, lineWidth: 1))
    }

    /// None | Unified | Standard, in the same segment style. "None" labels the
    /// off scheme here (the dropdown calls it "Default").
    private var schemeControl: some View {
        HStack(spacing: 0) {
            ForEach([Coloring.off, .unified, .standard], id: \.self) { c in
                segment(title: c == .off ? "None" : c.displayName, selected: draft.scheme == c) {
                    draft.changeScheme(c)
                }
            }
        }
        .frame(height: 24)
        .background(Pane.field)
        .overlay(Rectangle().strokeBorder(Pane.border, lineWidth: 1))
    }

    /// One segment button (recessed selection, no accent), shared by the kind and
    /// scheme controls.
    private func segment(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    if selected {
                        Rectangle().fill(
                            Color.black.opacity(0.28)
                                .shadow(.inner(color: .black.opacity(0.55), radius: 3, y: 1.5))
                        )
                    } else {
                        Rectangle().fill(Color.white.opacity(0.10))
                    }
                }
                .foregroundStyle(selected ? Pane.text : Pane.muted)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - Heading grid

    /// The heading swatch grid, sized to the scheme. Header labels (H1/H2/H3 or
    /// Color) sit above the wells. Absent under None, so the window closes up with
    /// no blank hole.
    @ViewBuilder private var headingSection: some View {
        if draft.scheme != .off {
            Grid(alignment: .center, horizontalSpacing: 6, verticalSpacing: 8) {
                GridRow {
                    if draft.kind == .dynamic {
                        Text("")
                        ForEach(0..<safeCount, id: \.self) { headingLabel($0) }
                        Text("")
                        ForEach(0..<safeCount, id: \.self) { headingLabel($0) }
                        Text("")
                    } else {
                        ForEach(0..<safeCount, id: \.self) { headingLabel($0) }
                    }
                }
                GridRow {
                    if draft.kind == .dynamic {
                        Image(systemName: "sun.max").font(.system(size: 12)).foregroundStyle(Pane.muted)
                            .accessibilityLabel("Light")
                        ForEach(0..<safeCount, id: \.self) { headingWell(.light, $0) }
                        Text("|").opacity(0.35)
                        ForEach(0..<safeCount, id: \.self) { headingWell(.dark, $0) }
                        Image(systemName: "moon.fill").font(.system(size: 12)).foregroundStyle(Pane.muted)
                            .accessibilityLabel("Dark")
                    } else {
                        ForEach(0..<safeCount, id: \.self) { headingWell(.light, $0) }
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func headingLabel(_ i: Int) -> some View {
        Text(slotLabels[i]).font(.system(size: 10)).foregroundStyle(Pane.muted)
    }

    private func headingWell(_ side: CustomDraft.Side, _ i: Int) -> some View {
        let binding = side == .light ? $draft.lights[i] : $draft.darks[i]
        return SquareColorWell(
            color: binding, size: wellSize,
            isSelected: draft.selectedWell == CustomDraft.SelectedWell(side: side, slot: i)
        ) {
            draft.selectedWell = CustomDraft.SelectedWell(side: side, slot: i)
        }
        .accessibilityLabel("\(slotLabels[i]) \(side == .light ? "light" : "dark") color")
    }

    // MARK: - Background

    /// The editor background: one well when static, a light │ dark pair when
    /// dynamic, plus the quick-pick strip and the saved-library row.
    private var backgroundSection: some View {
        VStack(spacing: 8) {
            Text("BACKGROUND")
                .font(.system(size: 9)).tracking(0.6)
                .foregroundStyle(Pane.muted).opacity(0.55)
            HStack(spacing: 6) {
                if draft.kind == .dynamic {
                    Image(systemName: "sun.max").font(.system(size: 12)).foregroundStyle(Pane.muted)
                        .accessibilityLabel("Light")
                    backgroundWell(.light)
                    Text("|").opacity(0.35)
                    backgroundWell(.dark)
                    Image(systemName: "moon.fill").font(.system(size: 12)).foregroundStyle(Pane.muted)
                        .accessibilityLabel("Dark")
                } else {
                    backgroundWell(.light)
                }
            }
            quickPickStrip
            if !savedBackgrounds.isEmpty { savedRow }
        }
        .frame(maxWidth: .infinity)
    }

    /// A background well. A panel pick marks the well panel-sourced (so Save adds
    /// it to the library); static mirrors the light well to the dark one so the
    /// identical-pair invariant survives editing. Activating clears the heading
    /// selection ring so it never points at a hidden well.
    private func backgroundWell(_ side: CustomDraft.Side) -> some View {
        let binding = Binding<Color>(
            get: {
                let well = side == .light ? draft.bgLight : draft.bgDark
                return Color(nsColor: NSColor(hex: well.hex) ?? .white)
            },
            set: { c in
                let well = CustomDraft.BackgroundWell(hex: CustomDraft.hex(c), fromPanel: true)
                if side == .light {
                    draft.bgLight = well
                    if draft.kind == .static { draft.bgDark = well }
                } else {
                    draft.bgDark = well
                }
            })
        return SquareColorWell(color: binding, size: wellSize) {
            draft.selectedWell = nil
        }
        .accessibilityLabel("Background \(side == .light ? "light" : "dark") color")
    }

    /// Default plus the three tinted preset pairs. Dynamic shows each as a
    /// light │ dark pair applied to both wells; static shows each side as its own
    /// single swatch applied to the one well.
    private var presetPairs: [(id: String, name: String, pair: ColorPair)] {
        [(id: "bg.default", name: "Default", pair: EditorBackground.defaultPair)]
            + BackgroundPreset.all.map { (id: $0.id, name: $0.name, pair: $0.pair) }
    }

    private var presetSingles: [(id: String, name: String, hex: String)] {
        presetPairs.flatMap { item in
            [(id: item.id + ".l", name: item.name + " light", hex: item.pair.light),
             (id: item.id + ".d", name: item.name + " dark", hex: item.pair.dark)]
        }
    }

    @ViewBuilder private var quickPickStrip: some View {
        HStack(spacing: 6) {
            if draft.kind == .dynamic {
                ForEach(presetPairs, id: \.id) { item in
                    Button { draft.applyPairBackground(item.pair) } label: {
                        HStack(spacing: 0) {
                            Rectangle().fill(Color(nsColor: item.pair.nsLight)).frame(width: 12, height: 16)
                            Rectangle().fill(Color(nsColor: item.pair.nsDark)).frame(width: 12, height: 16)
                        }
                        .overlay(Rectangle().strokeBorder(Color(white: 0.47).opacity(0.5), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(item.name) background")
                }
            } else {
                ForEach(presetSingles, id: \.id) { item in
                    Button { draft.applySingleBackground(item.hex) } label: {
                        Rectangle().fill(Color(nsColor: NSColor(hex: item.hex) ?? .white))
                            .frame(width: 14, height: 16)
                            .overlay(Rectangle().strokeBorder(Color(white: 0.47).opacity(0.5), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(item.name) background")
                }
            }
        }
    }

    /// The saved backgrounds row: each library swatch applies to the well, with a
    /// small x that removes it from the library.
    private var savedRow: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 22), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(savedBackgrounds, id: \.self) { hex in
                Button { draft.applySingleBackground(hex) } label: {
                    Rectangle().fill(Color(nsColor: NSColor(hex: hex) ?? .white))
                        .frame(width: 18, height: 18)
                        .overlay(Rectangle().strokeBorder(Color(white: 0.47).opacity(0.5), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Saved background \(hex)")
                .overlay(alignment: .topTrailing) {
                    Button {
                        BackgroundLibrary.remove(hex)
                        libraryTick += 1
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(Pane.muted)
                    }
                    .buttonStyle(.plain)
                    .offset(x: 5, y: -5)
                    .accessibilityLabel("Remove saved background \(hex)")
                }
            }
        }
        .padding(.top, 2)
    }

    // MARK: - Name

    private var nameField: some View {
        TextField("Name", text: $draft.name)
            .textFieldStyle(.plain)
            .font(.system(size: 11))
            .padding(.horizontal, 8)
            .frame(height: 26)
            .frame(maxWidth: .infinity)
            .background(Pane.field)
            .overlay(Rectangle().strokeBorder(Pane.border, lineWidth: 1))
            .onChange(of: draft.name) { _, v in if v.count > 10 { draft.name = String(v.prefix(10)) } }
    }

    /// The delete confirmation page, styled like the editor (same window chrome,
    /// padding, and square buttons) so it reads as the same window asking a
    /// question. The red-outline Delete is identical to the editor's Delete (same
    /// style, side, and width); Cancel takes Save's neutral slot and returns to the
    /// editor. A sibling page rather than a dimmed overlay (see `body`).
    private var deleteConfirmation: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Delete “\(draft.name)”?")
                .font(.system(size: 13, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .center)
            Text("This permanently removes the custom theme and can’t be undone.")
                .font(.system(size: 11))
                .foregroundStyle(Pane.muted)
                .fixedSize(horizontal: false, vertical: true)
            // Delete is the same button as the editor's (red outline, left, same
            // width); Cancel takes Save's neutral slot on the right.
            HStack(spacing: 10) {
                Button("Delete") { performDelete() }
                    .buttonStyle(SquareButtonStyle(outline: Self.deleteRed, width: Self.actionWidth))
                Spacer()
                Button("Cancel") { showDeleteConfirm = false }
                    .buttonStyle(SquareButtonStyle(width: Self.actionWidth))
            }
            .frame(maxWidth: .infinity)
        }
        .padding(EdgeInsets(top: 26, leading: 20, bottom: 20, trailing: 20))
        .foregroundStyle(Pane.text)
    }

    // MARK: - Actions

    /// Remove the saved custom and close. The Settings window repoints its
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

    /// Persist the built palette into the theme library (insert or update), add
    /// any panel-picked backgrounds to the library, and select the theme back in
    /// the Settings window (via `savedId`), then close. The Custom builder only
    /// DEFINES a palette; choosing it and applying it to the document happens in
    /// the Settings window, like any preset.
    private func save() {
        let palette = draft.buildPalette()
        var all = ThemeSettings.decodeCustoms(customsData)
        if let idx = all.firstIndex(where: { $0.id == palette.id }) { all[idx] = palette } else { all.append(palette) }
        customsData = ThemeSettings.encodeCustoms(all)
        for hex in draft.panelPickedBackgrounds() { BackgroundLibrary.add(hex) }
        draft.editingId = palette.id
        draft.savedId = palette.id
        dismiss()
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
        // The Theme Builder window floats above the document; float the shared color
        // panel to the same level so it still comes forward over the window when
        // picking a color (otherwise the floating window would trap it behind).
        NSColorPanel.shared.level = .floating
        onActivate()                    // tell SwiftUI which swatch is now selected
    }

    /// NSColorWell's default mouseDown TOGGLES: clicking an already-active well
    /// deactivates it, after which panel picks go nowhere; with invisible wells
    /// that read as "click the box then pick a color sometimes does nothing".
    /// A click here always makes this well the target and fronts the panel.
    override func mouseDown(with event: NSEvent) {
        activate(true)
        NSColorPanel.shared.makeKeyAndOrderFront(nil)
    }
}

/// Positions the Theme Builder window (once) just left of the Settings window,
/// so that window's live preview stays visible while editing. (Both windows pin
/// their appearance to the OS via `SystemWindowAppearance`, matching the system
/// color picker.)
struct PositionBesideSettings: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { NSView() }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard !context.coordinator.positioned else { return }
        DispatchQueue.main.async {
            guard let w = nsView.window else { return }
            context.coordinator.positioned = true
            let visible = (w.screen ?? NSScreen.main)?.visibleFrame
            if let appWin = NSApp.windows.first(where: { $0.title == "Settings" && $0 !== w }) {
                let f = appWin.frame
                // Prefer just-left of the Settings window so its live preview
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

/// Raises and keys the Theme Builder window once, when it appears, so it takes
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
