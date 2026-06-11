import SwiftUI
import AppKit

/// The Settings window's chrome palette: semantic system colors that resolve
/// against the window's appearance. `SystemWindowAppearance` pins the window to
/// the OS appearance (like the system color picker), so these follow the OS,
/// light in Light, dark in Dark, independent of the editor Mode. (The preview
/// pane still shows the chosen Mode's light/dark.)
enum Pane {
    static let window = Color(nsColor: .windowBackgroundColor)   // matches the system color picker
    static let field  = Color(nsColor: .textBackgroundColor)     // dark wells: boxes, dropdowns, buttons
    static let border = Color(nsColor: .separatorColor)          // hairline borders
    static let text   = Color(nsColor: .labelColor)              // values, icons, titles
    static let muted  = Color(nsColor: .secondaryLabelColor)     // secondary labels / subheadings
}

/// Pins the host window to the OS appearance. The settings windows use this
/// instead of `.preferredColorScheme`, which doesn't set `NSWindow.appearance`
/// for an auxiliary `Window` scene, leaving the Pane.* semantic colors to
/// resolve against whatever appearance a document window last forced via its
/// editor Mode. SwiftUI re-runs `updateNSView` whenever the window's content
/// updates, so the pin re-asserts on every interaction. (Like the sibling
/// `PositionBesideSettings`, the async hop covers the first pass where the view
/// isn't attached to its window yet.)
struct SystemWindowAppearance: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            let dark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        }
    }
}

/// Keeps an auxiliary window above the document windows: clicking a document
/// window no longer drops this one behind it. Used on the Settings and Custom
/// Theme windows. The shared NSColorPanel is floated to the same level (see
/// PanelColorWell.activate) so picking a color still comes forward over the
/// Custom Theme window instead of being trapped behind it.
struct FloatAboveDocument: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            if window.level != .floating { window.level = .floating }
        }
    }
}

/// Pure geometry for keeping a window on screen. macOS frame autosave can
/// restore an auxiliary `Window` partway off the screen edge (the more so after
/// heavy reposition churn); this nudges a frame back fully inside `visible`
/// (a screen's `visibleFrame`, which already excludes the menu bar and Dock).
/// A frame already inside `visible` is returned unchanged, so a position the
/// user deliberately dragged to still sticks. A frame larger than the visible
/// area on an axis is pinned to that axis's leading edge, top for Y, so the
/// title bar stays reachable. Coordinates are AppKit's (origin bottom-left).
enum WindowPlacement {
    static func onScreen(_ frame: CGRect, in visible: CGRect) -> CGRect {
        if visible.contains(frame) { return frame }
        var f = frame
        if f.width >= visible.width {
            f.origin.x = visible.minX
        } else {
            f.origin.x = min(max(f.minX, visible.minX), visible.maxX - f.width)
        }
        if f.height >= visible.height {
            f.origin.y = visible.maxY - f.height   // keep the title bar (top) on screen
        } else {
            f.origin.y = min(max(f.minY, visible.minY), visible.maxY - f.height)
        }
        return f
    }
}

/// Pulls the host window fully on screen the first time it attaches, using
/// `WindowPlacement.onScreen`. Applied to the Settings window (and reused by
/// `PositionBesideSettings` for the Custom Theme window). Runs once per
/// attachment, a frame the user later drags somewhere on-screen is left alone.
struct KeepOnScreen: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { NSView() }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard !context.coordinator.done else { return }
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            context.coordinator.done = true
            guard let visible = (window.screen ?? NSScreen.main)?.visibleFrame else { return }
            let fixed = WindowPlacement.onScreen(window.frame, in: visible)
            if fixed != window.frame { window.setFrame(fixed, display: true) }
        }
    }

    final class Coordinator { var done = false }
}

struct SettingsView: View {
    @EnvironmentObject private var theme: ThemeController
    @EnvironmentObject private var customDraft: CustomDraft
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    @AppStorage(ThemeSettings.customsKey) private var customsData = Data()

    // Working copy, edits here don't reach the document until Apply/Save.
    @State private var wcSchemeRaw = Coloring.off.rawValue
    @State private var wcThemeId = ColorTheming.defaultStandardId
    @State private var wcFontSize = Double(FontSize.standard)
    @State private var wcAppearanceRaw = AppAppearance.system.rawValue
    @State private var wcFontFamilyId = FontFamily.default.id
    @State private var wcCursorStyleRaw = CursorStyle.bar.rawValue
    @State private var wcCursorBlink = true
    @State private var wcBackgroundModeRaw = BackgroundMode.default.rawValue
    @State private var wcCustomBackgroundHex: String?
    /// Bump to open the shared color panel on the background well (picking
    /// Custom with no color yet, or the pencil).
    @State private var backgroundPickerActivation = 0
    @State private var sizeText = ""

    // The Editing tab. Its controls take effect immediately (standard macOS
    // settings behavior), unlike the Appearance tab's transactional Apply/Save.
    @State private var tab: SettingsTab = .appearance
    @AppStorage(SpellingPref.spellingKey) private var checkSpelling = true
    @AppStorage(SpellingPref.grammarKey) private var checkGrammar = false
    @State private var windowWidthText = ""
    @State private var windowHeightText = ""
    @FocusState private var focusedSizeField: SizeField?

    enum SizeField: Hashable { case width, height }

    // Which dropdown (if any) is open, and the on-screen frame of each trigger
    // box so the in-window dropdown can sit flush beneath it.
    @State private var openMenu: MenuField?
    @State private var fieldFrames: [MenuField: CGRect] = [:]

    static let space = "settingsMenu"
    private let wideWidth: CGFloat = 225
    // Wide enough for the Background box to show its selected option's label
    // ("Default" / "Custom+") plus swatch and chevron; Scheme, Size, and the
    // Blink toggle share it so the right column stays uniform.
    private let segWidth: CGFloat = 110
    private let rowHeight: CGFloat = 32

    private var wcColoring: Coloring { Coloring(rawValue: wcSchemeRaw) ?? .off }
    private var wcAppearance: AppAppearance { AppAppearance(rawValue: wcAppearanceRaw) ?? .system }
    private var customs: [Palette] { ThemeSettings.decodeCustoms(customsData) }
    private var wcPalette: Palette? {
        ThemeSettings.resolvePalette(coloring: wcColoring, themeId: wcThemeId, customs: customs)
    }
    private var wcFontFamily: FontFamily { FontFamily.resolve(id: wcFontFamilyId) }
    private var wcBackgroundMode: BackgroundMode { BackgroundMode(rawValue: wcBackgroundModeRaw) ?? .default }
    /// The stored Custom color (even while Default is selected, for the Custom
    /// row's swatch and pencil); nil until one is picked or for a bad hex.
    private var wcStoredCustomColor: NSColor? { wcCustomBackgroundHex.flatMap { NSColor(hex: $0) } }
    /// The custom color only when Custom is the active selection (what the
    /// preview paints).
    private var wcActiveCustomColor: NSColor? {
        EditorBackground.customColor(mode: wcBackgroundMode, hex: wcCustomBackgroundHex)
    }
    // Apply lights up when the selection differs from what the editor is
    // currently showing (the applied/effective state), so you can always apply
    // your choice, even if it equals the saved value. Save lights up when the
    // selection differs from the persisted (saved) value.
    private var applyDirty: Bool {
        wcColoring != theme.coloring
        || wcThemeId != theme.themeId
        || wcFontSize != theme.fontSize
        || wcAppearance != theme.appearance
        || wcFontFamilyId != theme.fontFamilyId
        || wcCursorStyleRaw != theme.cursorStyle.rawValue
        || wcCursorBlink != theme.cursorBlink
        || wcBackgroundModeRaw != theme.backgroundMode.rawValue
        || wcCustomBackgroundHex != theme.customBackgroundHex
    }
    private var saveDirty: Bool {
        wcSchemeRaw != theme.savedColoring.rawValue
        || wcThemeId != theme.savedThemeId
        || wcFontSize != theme.savedFontSize
        || wcAppearanceRaw != theme.savedAppearance.rawValue
        || wcFontFamilyId != theme.savedFontFamilyId
        || wcCursorStyleRaw != theme.savedCursorStyle.rawValue
        || wcCursorBlink != theme.savedCursorBlink
        || wcBackgroundModeRaw != theme.savedBackgroundMode.rawValue
        || wcCustomBackgroundHex != theme.savedCustomBackground
    }
    // A new custom theme is being edited in the Custom Theme window but hasn't been
    // saved yet, so it has no committable id. The preview shows the live draft, but
    // Apply/Save here would commit the previously-selected theme, so they're
    // disabled until the draft is saved (which selects it via savedId).
    private var draftUncommitted: Bool { customDraft.active && customDraft.editingId == nil }

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                tabBar
                    .padding(EdgeInsets(top: 20, leading: 20, bottom: 0, trailing: 20))
                if tab == .appearance {
                    content
                } else {
                    editingTab
                }
            }
            if tab == .appearance {
                dropdownLayer
            }
        }
        .frame(width: 389)   // 20 + wideWidth + 14 + segWidth + 20
        // Switching tabs closes any open dropdown so it cannot strand over the
        // other tab's content.
        .onChange(of: tab) { _, _ in openMenu = nil }
        .background(Pane.window)
        .coordinateSpace(name: Self.space)
        .onPreferenceChange(FieldFrameKey.self) { fieldFrames = $0 }
        // Follow the OS appearance (like the real system color picker),
        // independent of the editor Mode the document windows force on
        // themselves. `.preferredColorScheme` only sets SwiftUI's environment, not
        // the host NSWindow.appearance, so the Pane.* semantic colors would
        // otherwise resolve against whatever a document window last forced. Pinning
        // the window to the live system appearance keeps this chrome tracking the
        // OS (light in Light, dark in Dark). The preview still shows the Mode.
        .background(SystemWindowAppearance())
        .background(FloatAboveDocument())
        // Invisible, zero-sized color well bridging the shared NSColorPanel to
        // the Background working copy. Mounted on the window root (not the
        // transient dropdown) so the panel keeps feeding color changes after the
        // dropdown closes. Opened programmatically via backgroundPickerActivation.
        .background(BackgroundColorWell(hex: $wcCustomBackgroundHex,
                                        activation: backgroundPickerActivation,
                                        initialColor: EditorBackground.defaultBackground(dark: wcAppearance.resolvesDark))
            .frame(width: 0, height: 0))
        // macOS frame autosave can restore this auxiliary window partway off the
        // screen edge; pull it back fully on screen on open (a dragged on-screen
        // position is left untouched).
        .background(KeepOnScreen())
        .onAppear { syncFromSaved(); reconcileThemeId(); syncWindowSizeFields() }
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
            // Cascade: the Custom Theme builder and the system color picker are
            // satellites of this window, never leave them orphaned when it closes.
            // (The builder's own onDisappear only re-focuses "Settings" while it
            // is still visible, so this can't resurrect a closing window.)
            NSApp.windows.first { $0.title == "Custom Theme" }?.close()
            // Leave the shared color panel in a known-good state. PanelColorWell
            // forces showsAlpha off and a floating level while picking; resetting
            // both here makes closing Settings self-sufficient instead of relying
            // on the Custom Theme window's teardown running first.
            NSColorPanel.shared.close()
            NSColorPanel.shared.level = .normal
            NSColorPanel.shared.showsAlpha = true
        }
        // When the Custom Theme window saves a palette, select it here.
        .onChange(of: customDraft.savedId) { _, id in
            if let id {
                wcSchemeRaw = customDraft.scheme.rawValue
                wcThemeId = id
            }
        }
        // A View-menu font command (Cmd-+/-/0) can change the size out from under
        // this window. Keep the Size working copy in sync as long as the user
        // hasn't started editing Size themselves.
        .onChange(of: theme.fontSize) { old, new in
            if wcFontSize == old, openMenu != .size {
                wcFontSize = new
                sizeText = "\(Int(new))"
            }
        }
        // Deleting the selected custom in the Custom Theme window drops its id;
        // repoint the working copy to whatever resolvePalette falls back to so the
        // Theme box and dropdown selection stay truthful (and Save can't persist a
        // dead id).
        .onChange(of: customsData) { _, _ in reconcileThemeId() }
        // Escape closes an open dropdown first, then (pressed again) dismisses the
        // window the same way Close does, revert any unsaved Apply.
        .onExitCommand {
            if openMenu != nil { openMenu = nil }
            else { theme.revertToSaved(); dismiss() }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                LabeledField(label: "Mode") {
                    ModeControl(appearanceRaw: $wcAppearanceRaw)
                        .frame(width: wideWidth, height: rowHeight)
                }
                LabeledField(label: "Background") {
                    backgroundBox.frame(width: segWidth, height: rowHeight)
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
            HStack(spacing: 14) {
                LabeledField(label: "Font") {
                    fontBox.frame(width: wideWidth, height: rowHeight)
                }
                LabeledField(label: "Size") {
                    SizeControl(fontSize: $wcFontSize, text: $sizeText, openMenu: $openMenu)
                        .frame(width: segWidth, height: rowHeight)
                }
            }
            HStack(spacing: 14) {
                LabeledField(label: "Cursor") {
                    CursorControl(styleRaw: $wcCursorStyleRaw)
                        .frame(width: wideWidth, height: rowHeight)
                }
                Toggle("Blink", isOn: $wcCursorBlink)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11))
                    .frame(width: segWidth, height: rowHeight)
            }
            ThemePreview(coloring: customDraft.active ? customDraft.scheme : wcColoring,
                         palette: customDraft.active ? customDraft.palette : wcPalette,
                         appearance: wcAppearance, fontSize: CGFloat(wcFontSize),
                         family: wcFontFamily,
                         customBackground: wcActiveCustomColor)
                .frame(maxWidth: .infinity)
            HStack(spacing: 10) {
                // No Close button: the title-bar close control and Escape already
                // revert any unsaved Apply and dismiss (via onDisappear), matching
                // the Custom Theme window. Apply and Save sit at the trailing edge.
                Spacer()
                Button("Apply") {
                    theme.apply(coloring: wcColoring, themeId: wcThemeId,
                                fontSize: wcFontSize, appearance: wcAppearance)
                    theme.applyFontFamily(wcFontFamilyId)
                    theme.applyCursor(style: CursorStyle(rawValue: wcCursorStyleRaw) ?? .bar, blink: wcCursorBlink)
                    theme.applyBackground(mode: wcBackgroundMode, hex: wcCustomBackgroundHex)
                }
                    .buttonStyle(SquareButtonStyle())
                    .disabled(!applyDirty || draftUncommitted)
                Button("Save") {
                    theme.save(coloring: wcColoring, themeId: wcThemeId,
                               fontSize: wcFontSize, appearance: wcAppearance)
                    theme.saveFontFamily(wcFontFamilyId)
                    theme.saveCursor(style: CursorStyle(rawValue: wcCursorStyleRaw) ?? .bar, blink: wcCursorBlink)
                    theme.saveBackground(mode: wcBackgroundMode, hex: wcCustomBackgroundHex)
                    dismiss()
                }
                    .buttonStyle(SquareButtonStyle())
                    .disabled(!saveDirty || draftUncommitted)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(EdgeInsets(top: 26, leading: 20, bottom: 20, trailing: 20))
        .foregroundStyle(Pane.text)
    }

    // MARK: - Tabs

    /// The Appearance | Editing segmented bar, styled like the Mode and Cursor
    /// segments so the window keeps one visual language.
    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(SettingsTab.allCases, id: \.self) { t in
                let selected = tab == t
                Button { tab = t } label: {
                    Text(t.rawValue)
                        .font(.system(size: 11))
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
        }
        .frame(height: 28)
        .background(Pane.field)
        .overlay(Rectangle().strokeBorder(Pane.border, lineWidth: 1))
        .foregroundStyle(Pane.text)
    }

    /// The Editing tab: immediate-effect editing defaults (no Apply/Save).
    private var editingTab: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 10) {
                caption("Spelling")
                Toggle("Check spelling as you type", isOn: Binding(
                    get: { checkSpelling },
                    set: { SpellingPref.setCheckSpelling($0) }
                ))
                .toggleStyle(.checkbox)
                .font(.system(size: 12))
                Toggle("Check grammar with spelling", isOn: Binding(
                    get: { checkGrammar },
                    set: { SpellingPref.setCheckGrammar($0) }
                ))
                .toggleStyle(.checkbox)
                .font(.system(size: 12))
            }
            VStack(alignment: .leading, spacing: 10) {
                caption("New windows")
                HStack(spacing: 8) {
                    Text("Width").font(.system(size: 12))
                    windowSizeField($windowWidthText, field: .width)
                    Text("Height").font(.system(size: 12)).padding(.leading, 8)
                    windowSizeField($windowHeightText, field: .height)
                    Text("points").font(.system(size: 11)).foregroundStyle(Pane.muted).padding(.leading, 4)
                }
                // Commit when a size field loses focus, not just on Return, so
                // a typed value is never silently discarded.
                .onChange(of: focusedSizeField) { old, _ in
                    if old != nil { commitWindowSizeFields() }
                }
                Button("Use Current Window") { captureCurrentWindowSize() }
                    .buttonStyle(SquareButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(EdgeInsets(top: 26, leading: 20, bottom: 20, trailing: 20))
        .foregroundStyle(Pane.text)
    }

    /// The same small uppercase caption the Appearance controls wear.
    private func caption(_ label: String) -> some View {
        Text(label.uppercased())
            .font(.system(size: 9))
            .tracking(0.6)
            .foregroundStyle(Pane.muted)
            .opacity(0.55)
    }

    /// A bordered numeric field matching the Size box; commits (and clamps)
    /// on Return or focus loss.
    private func windowSizeField(_ text: Binding<String>, field: SizeField) -> some View {
        TextField("", text: text)
            .textFieldStyle(.plain)
            .multilineTextAlignment(.center)
            .font(.system(size: 11))
            .frame(width: 56, height: 26)
            .background(Pane.field)
            .overlay(Rectangle().strokeBorder(Pane.border, lineWidth: 1))
            .focused($focusedSizeField, equals: field)
            .onSubmit { commitWindowSizeFields() }
    }

    /// Parse, clamp, persist, and reformat both size fields.
    private func commitWindowSizeFields() {
        NewWindowSize.set(width: parseSize(windowWidthText, fallback: NewWindowSize.width),
                          height: parseSize(windowHeightText, fallback: NewWindowSize.height))
        syncWindowSizeFields()
    }

    /// Numeric parse that keeps a decimal entry sane: "760.5" reads as 760.5,
    /// not as digit-stripped 7605 racing into the clamp ceiling.
    private func parseSize(_ text: String, fallback: Double) -> Double {
        Double(text.trimmingCharacters(in: .whitespaces))
            ?? Double(text.filter(\.isNumber))
            ?? fallback
    }

    private func syncWindowSizeFields() {
        windowWidthText = "\(Int(NewWindowSize.width))"
        windowHeightText = "\(Int(NewWindowSize.height))"
    }

    /// Capture the frontmost document window's content size as the new-window
    /// default. Panels (the color picker) and the auxiliary windows are
    /// skipped; with no document window open this beeps and changes nothing.
    private func captureCurrentWindowSize() {
        let aux: Set<String> = ["Settings", "Custom Theme", "Help"]
        guard let doc = NSApp.orderedWindows.first(where: {
            $0.isVisible && !($0 is NSPanel) && !aux.contains($0.title)
        }) else {
            NSSound.beep()
            return
        }
        let size = doc.contentLayoutRect.size
        NewWindowSize.set(width: size.width, height: size.height)
        syncWindowSizeFields()
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

    /// The Background trigger: the selected option's name plus its swatch
    /// right-aligned against the chevron, like the Theme box.
    private var backgroundBox: some View {
        Button { toggle(.background) } label: {
            HStack(spacing: 0) {
                Text(wcBackgroundMode == .custom ? "Custom+" : "Default")
                    .font(.system(size: 11))
                    .lineLimit(1)
                Spacer(minLength: 8)
                if wcBackgroundMode == .custom {
                    if let color = wcStoredCustomColor {
                        Swatch(color: Color(nsColor: color))
                    } else {
                        PlusSwatch()
                    }
                } else {
                    Swatch(color: Color(nsColor: EditorBackground.defaultBackground(dark: wcAppearance.resolvesDark)))
                }
                Image(systemName: "chevron.down").font(.system(size: 8)).opacity(0.5)
                    .padding(.leading, 8)
                    .rotationEffect(.degrees(openMenu == .background ? 180 : 0))
                    .animation(.easeInOut(duration: 0.15), value: openMenu == .background)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Pane.field)
            .overlay(Rectangle().strokeBorder(Pane.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Background")
        .reportsFrame(.background)
    }

    private var fontBox: some View {
        Button { toggle(.font) } label: {
            HStack(spacing: 0) {
                Text(wcFontFamily.displayName)
                    .font(Font(wcFontFamily.font(size: 12) as CTFont))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Image(systemName: "chevron.down").font(.system(size: 8)).opacity(0.5)
                    .rotationEffect(.degrees(openMenu == .font ? 180 : 0))
                    .animation(.easeInOut(duration: 0.15), value: openMenu == .font)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Pane.field)
            .overlay(Rectangle().strokeBorder(Pane.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .reportsFrame(.font)
    }

    private var schemeBox: some View {
        Button { toggle(.scheme) } label: {
            HStack(spacing: 0) {
                Text(wcColoring.displayName).font(.system(size: 11)).lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.down").font(.system(size: 8)).opacity(0.5)
                    .rotationEffect(.degrees(openMenu == .scheme ? 180 : 0))
                    .animation(.easeInOut(duration: 0.15), value: openMenu == .scheme)
            }
            .padding(.horizontal, 7)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Pane.field)
            .overlay(Rectangle().strokeBorder(Pane.border, lineWidth: 1))
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
            InlineDropdown(items: items(for: field), keyboardNav: field != .size)
                .id(field)
                .frame(width: frame.width, alignment: .topLeading)
                .offset(x: frame.minX, y: frame.maxY)
        }
    }

    private func items(for field: MenuField) -> [DropdownItem] {
        switch field {
        case .theme:
            var rows = ColorTheming.presets(for: wcColoring).map { p in
                DropdownItem(id: p.id, kind: .palette(p), selected: p.id == wcThemeId,
                             action: { pickTheme(p.id) })
            }
            let mine = customs.filter { $0.scheme == wcColoring }
            if !mine.isEmpty {
                rows.append(DropdownItem(id: "hdr.custom", kind: .header("Custom")))
                rows.append(contentsOf: mine.map { p in
                    DropdownItem(
                        id: p.id, kind: .palette(p), selected: p.id == wcThemeId,
                        action: { pickTheme(p.id) },
                        onEdit: {
                            openMenu = nil
                            customDraft.beginEditing(p)
                            openWindow(id: CustomThemeScene.id)
                        })
                })
            }
            rows.append(DropdownItem(id: "custom.plus", kind: .customPlus(wcColoring), action: {
                openMenu = nil
                customDraft.begin(scheme: wcColoring)
                openWindow(id: CustomThemeScene.id)
            }))
            return rows
        case .scheme:
            return Coloring.allCases.map { c in
                DropdownItem(id: c.rawValue, kind: .text(c.displayName), selected: c == wcColoring,
                             action: { pickScheme(c) })
            }
        case .size:
            return SizeControl.sizes.map { s in
                DropdownItem(id: "\(s)", kind: .text("\(s)"), selected: sizeText == "\(s)",
                             centered: true, action: { pickSize(s) })
            }
        case .font:
            return FontFamily.all.map { fam in
                DropdownItem(id: fam.id, kind: .fontSample(fam), selected: fam.id == wcFontFamilyId,
                             action: { pickFont(fam.id) })
            }
        case .background:
            return [
                DropdownItem(id: "bg.default",
                             kind: .backgroundSwatch(EditorBackground.defaultBackground(dark: wcAppearance.resolvesDark)),
                             selected: wcBackgroundMode == .default,
                             action: { pickBackground(.default) }),
                DropdownItem(id: "bg.custom",
                             kind: .backgroundCustom(wcStoredCustomColor),
                             selected: wcBackgroundMode == .custom,
                             action: { pickBackground(.custom) },
                             onEdit: wcStoredCustomColor == nil ? nil : { openBackgroundPicker() }),
            ]
        }
    }

    private func toggle(_ field: MenuField) { openMenu = (openMenu == field ? nil : field) }

    private func pickTheme(_ id: String) { wcThemeId = id; openMenu = nil }
    private func pickFont(_ id: String) { wcFontFamilyId = id; openMenu = nil }

    /// Picking Custom with no color yet goes straight to the color panel (the
    /// blank "+" swatch); with a remembered color it just selects it (the pencil
    /// reopens the panel).
    private func pickBackground(_ mode: BackgroundMode) {
        wcBackgroundModeRaw = mode.rawValue
        openMenu = nil
        if mode == .custom, wcCustomBackgroundHex == nil { backgroundPickerActivation += 1 }
    }

    /// The Custom row's pencil: select Custom and reopen the panel on the
    /// stored color.
    private func openBackgroundPicker() {
        wcBackgroundModeRaw = BackgroundMode.custom.rawValue
        openMenu = nil
        backgroundPickerActivation += 1
    }

    private func pickScheme(_ c: Coloring) {
        defer { openMenu = nil }
        // Re-picking the scheme you're already on keeps the chosen theme; only a
        // real scheme change resets to that scheme's default palette.
        guard c != wcColoring else { return }
        wcSchemeRaw = c.rawValue
        switch c {
        case .off: break
        case .standard: wcThemeId = ColorTheming.defaultStandardId
        case .unified: wcThemeId = ColorTheming.defaultUnifiedId
        }
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
        wcFontFamilyId = theme.savedFontFamilyId
        wcCursorStyleRaw = theme.savedCursorStyle.rawValue
        wcCursorBlink = theme.savedCursorBlink
        wcBackgroundModeRaw = theme.savedBackgroundMode.rawValue
        wcCustomBackgroundHex = theme.savedCustomBackground
        sizeText = "\(Int(theme.savedFontSize))"
    }

    /// If the selected theme id no longer resolves to itself (e.g. the custom it
    /// pointed at was deleted), repoint the working copy to whatever the resolver
    /// falls back to, so the Theme box label and the dropdown's selected highlight
    /// match what is actually drawn.
    private func reconcileThemeId() {
        guard wcColoring != .off, let resolved = wcPalette, resolved.id != wcThemeId else { return }
        wcThemeId = resolved.id
    }

}

// MARK: - Dropdown plumbing

/// Identifies which trigger box a dropdown belongs to.
enum MenuField: Hashable { case theme, scheme, size, font, background }

/// The Settings window's tabs: Appearance holds the transactional theme and
/// editor-look controls; Editing holds the immediate-effect editing defaults.
enum SettingsTab: String, CaseIterable {
    case appearance = "Appearance"
    case editing = "Editing"
}

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
        case fontSample(FontFamily) // family name rendered in its own face
        case backgroundSwatch(NSColor)   // Background's Default row: the mode's bg
        case backgroundCustom(NSColor?)  // Background's Custom row: the picked color, or nil = blank "+"
    }
    let id: String
    let kind: Kind
    var selected = false
    var centered = false
    var action: (() -> Void)? = nil
    // Custom palette rows only, drives the trailing pencil (edit) icon.
    var onEdit: (() -> Void)? = nil
}

/// A seamless in-window dropdown: a flush list of rows the exact width of its
/// trigger box, sharp-edged and opaque, with no system menu chrome. It renders
/// inside the window (not a floating menu window), so it reads as attached and
/// inherits the window's light/dark Mode.
struct InlineDropdown: View {
    let items: [DropdownItem]
    /// Theme/Scheme dropdowns handle arrow-key / Return nav; the Size dropdown
    /// leaves the keys to its text field, so it opts out. (Escape stays on the
    /// SettingsView `.onExitCommand` path, which closes the open dropdown.)
    var keyboardNav = true
    /// Row metrics (matching DropdownRow) so the list can size itself to its
    /// content without measuring, a measured height inside a ScrollView never
    /// settles reliably.
    static let rowHeight: CGFloat = 24
    static let headerHeight: CGFloat = 21
    /// The list must end above the window's bottom buttons (a clear gap before the
    /// window bottom). The actual cap is this ceiling snapped DOWN to a whole row
    /// (see `snappedHeight`), so the bottom visible row is never sliced in half; a
    /// taller list scrolls within it.
    static let ceiling: CGFloat = 204

    @State private var scrollOffset: CGFloat = 0
    /// The highlighted row, driven by BOTH keyboard nav and mouse hover, so the
    /// two share one highlight instead of fighting. nil = nothing highlighted.
    @State private var activeIndex: Int?
    @State private var keyMonitor: Any?

    /// The height of a single row by kind.
    private static func height(for item: DropdownItem) -> CGFloat {
        if case .header = item.kind { return headerHeight }
        return rowHeight
    }

    /// The next selectable row index from `current` moving by `step` (+1 = down,
    /// -1 = up), skipping headers / non-selectable rows (action == nil) and
    /// clamping at the ends (no wrap). With no `current`, returns the first
    /// (down) or last (up) selectable row.
    static func nextSelectable(from current: Int?, step: Int, items: [DropdownItem]) -> Int? {
        let selectable = items.indices.filter { items[$0].action != nil }
        guard !selectable.isEmpty else { return nil }
        guard let current, let pos = selectable.firstIndex(of: current) else {
            return step > 0 ? selectable.first : selectable.last
        }
        let next = pos + (step > 0 ? 1 : -1)
        guard next >= 0, next < selectable.count else { return current }   // clamp
        return selectable[next]
    }

    /// The selectable row at a vertical offset within the scrolled content, or
    /// nil if the offset lands on a header or outside the list, turns a single
    /// container-level hover location into the highlighted row (one tracking
    /// area instead of one per row, which the 2019 Intel MBP handles far better).
    static func rowIndex(atContentY y: CGFloat, items: [DropdownItem]) -> Int? {
        guard y >= 0 else { return nil }
        var top: CGFloat = 0
        for i in items.indices {
            let h = height(for: items[i])
            if y >= top && y < top + h { return items[i].action != nil ? i : nil }
            top += h
        }
        return nil
    }

    /// The largest height <= `ceiling` that ends exactly on a row boundary of
    /// `items`, so the bottom visible row is always whole. If the whole list fits
    /// under `ceiling`, returns the full content height (no scroll). Never returns
    /// less than the first row. (A flat cap can't do this: a 21pt header shifts the
    /// row boundaries off the 24pt grid, so a fixed number re-clips a later row.)
    static func snappedHeight(items: [DropdownItem], ceiling: CGFloat) -> CGFloat {
        let content = items.reduce(CGFloat(0)) { $0 + height(for: $1) }
        if content <= ceiling { return content }
        var top: CGFloat = 0
        var lastBoundary: CGFloat = 0
        for item in items {
            let next = top + height(for: item)
            if next <= ceiling { lastBoundary = next; top = next } else { break }
        }
        return lastBoundary > 0 ? lastBoundary : (items.first.map { height(for: $0) } ?? 0)
    }

    /// The scroll thumb's height for a `viewport` over `content` (floored at 28pt
    /// so it stays grabbable on very long lists).
    static func thumbHeight(viewport: CGFloat, content: CGFloat) -> CGFloat {
        guard content > 0 else { return viewport }
        return max(28, viewport * viewport / content)
    }

    /// The thumb's vertical offset for a scroll position, mapping [0, maxScroll]
    /// onto the free track [0, viewport - thumbHeight].
    static func thumbOffset(scroll: CGFloat, viewport: CGFloat, content: CGFloat) -> CGFloat {
        let maxScroll = content - viewport
        guard maxScroll > 0 else { return 0 }
        let th = thumbHeight(viewport: viewport, content: content)
        return min(1, max(0, scroll / maxScroll)) * (viewport - th)
    }

    private var contentHeight: CGFloat {
        items.reduce(CGFloat(0)) { $0 + Self.height(for: $1) }
    }
    private var height: CGFloat { Self.snappedHeight(items: items, ceiling: Self.ceiling) }
    private var scrollable: Bool { contentHeight > height + 0.5 }
    private var thumbHeight: CGFloat { Self.thumbHeight(viewport: height, content: contentHeight) }
    private var thumbOffset: CGFloat { Self.thumbOffset(scroll: scrollOffset, viewport: height, content: contentHeight) }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                        DropdownRow(item: item, isActive: activeIndex == idx)
                    }
                }
                // A SwiftUI GeometryReader does not track a macOS ScrollView's live
                // scroll position (the measured content frame stays put), so read the
                // underlying NSScrollView's clip-view bounds directly instead.
                .background(ScrollObserver { scrollOffset = max(0, $0) })
            }
            .scrollIndicators(.hidden)
            .frame(height: height)
            .background(Pane.field)
            // One container-level hover tracker maps the pointer to a row, instead
            // of a tracking area per row, far snappier on the 2019 Intel MBP, and
            // writes the SAME activeIndex the keyboard does, so mouse and keyboard
            // share a single highlight.
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let loc): activeIndex = Self.rowIndex(atContentY: loc.y + scrollOffset, items: items)
                case .ended: activeIndex = nil
                }
            }
            // An opaque gutter masking the scrollbar lane with the dropdown's own
            // background, so a selected/hovered row's full-width highlight stops
            // cleanly just left of the thumb instead of bleeding under it. The 9pt
            // width clears the row content (inset 10pt), so swatch alignment is
            // unchanged.
            .overlay(alignment: .trailing) {
                if scrollable {
                    Pane.field.frame(width: 9).frame(maxHeight: .infinity).allowsHitTesting(false)
                }
            }
            // A custom floating scroll indicator: always visible when the list
            // scrolls, drawn over the gutter so it never pushes the rows.
            .overlay(alignment: .topTrailing) {
                if scrollable {
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(Color.primary.opacity(0.35))
                        .frame(width: 5, height: thumbHeight)
                        .offset(y: thumbOffset)
                        .padding(.trailing, 2)
                        .allowsHitTesting(false)
                }
            }
            .overlay(Rectangle().strokeBorder(Color.primary.opacity(0.3), lineWidth: 1).allowsHitTesting(false))
            .foregroundStyle(Pane.text)
            .onAppear {
                guard keyboardNav else { return }
                activeIndex = items.firstIndex(where: { $0.selected })
                    ?? Self.nextSelectable(from: nil, step: 1, items: items)
                installKeyMonitor(proxy)
            }
            .onDisappear { removeKeyMonitor() }
        }
    }

    /// Move the keyboard highlight and scroll it into view.
    private func move(_ step: Int, _ proxy: ScrollViewProxy) {
        guard let next = Self.nextSelectable(from: activeIndex, step: step, items: items) else { return }
        activeIndex = next
        proxy.scrollTo(items[next].id, anchor: .center)
    }

    // Arrow / Return / Escape are driven by a local key monitor rather than
    // SwiftUI focus: `@FocusState` on this transient overlay (opened, closed, and
    // reopened from the same trigger) failed to re-take focus on reopen, so the
    // keys silently stopped working the second time. A local monitor is
    // deterministic. It is scoped to the Settings window (so it never steals
    // keys from a document window) and torn down when the dropdown closes.
    private func installKeyMonitor(_ proxy: ScrollViewProxy) {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard NSApp.keyWindow?.title == "Settings" else { return event }
            switch event.keyCode {
            case 126: move(-1, proxy); return nil          // Up
            case 125: move(1, proxy); return nil           // Down
            case 36, 76:                                   // Return / Enter
                if let i = activeIndex, let act = items[i].action { act(); return nil }
                return event
            default: return event                          // Escape etc. → onExitCommand
            }
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }
}

/// Reports the enclosing NSScrollView's vertical scroll offset to SwiftUI so the
/// custom scroll indicator can follow it. A SwiftUI GeometryReader does not see a
/// macOS ScrollView's live scroll (its measured content frame stays put), so this
/// observes the underlying NSClipView's bounds directly.
private struct ScrollObserver: NSViewRepresentable {
    var onScroll: (CGFloat) -> Void

    func makeNSView(context: Context) -> NSView {
        let v = NSView(frame: .zero)
        DispatchQueue.main.async { context.coordinator.attach(from: v) }
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onScroll = onScroll
        // Retry attach only until the observer is registered; once attached, skip
        // the redundant re-dispatch on every scroll-driven re-render.
        if !context.coordinator.isAttached {
            DispatchQueue.main.async { context.coordinator.attach(from: nsView) }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(onScroll) }

    final class Coordinator: NSObject {
        var onScroll: (CGFloat) -> Void
        private weak var clip: NSClipView?
        var isAttached: Bool { clip != nil }
        init(_ onScroll: @escaping (CGFloat) -> Void) { self.onScroll = onScroll }

        /// Find the enclosing NSScrollView's clip view and observe its bounds.
        func attach(from view: NSView) {
            guard let clip = view.enclosingScrollView?.contentView, clip !== self.clip else { return }
            if let old = self.clip {
                NotificationCenter.default.removeObserver(self, name: NSView.boundsDidChangeNotification, object: old)
            }
            self.clip = clip
            clip.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(self, selector: #selector(boundsChanged),
                                                   name: NSView.boundsDidChangeNotification, object: clip)
            report()
        }

        @objc private func boundsChanged() { report() }
        private func report() { if let clip { onScroll(clip.bounds.origin.y) } }
        deinit { NotificationCenter.default.removeObserver(self) }
    }
}

private struct DropdownRow: View {
    let item: DropdownItem
    /// Highlighted by the parent (keyboard nav or the container-level hover
    /// tracker), the row no longer tracks its own hover.
    var isActive = false

    var body: some View {
        switch item.kind {
        case .header(let title):
            Text(title.uppercased())
                .font(.system(size: 9)).tracking(0.6)
                .foregroundStyle(Pane.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.top, 7).padding(.bottom, 3)
        case .palette(let p):
            paletteRow(p)
        case .customPlus(let scheme):
            row {
                Text("Custom+").font(.system(size: 11))
                Spacer(minLength: 8)
                emptyTrio(count: scheme == .standard ? 3 : 1)
                // Reserve the same trailing slot the palette rows give the pencil
                // icon, so Custom+'s swatches sit in the same column as every other
                // row instead of 16pt to the right.
                Color.clear.frame(width: iconSlot, height: 1)
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
        case .fontSample(let fam):
            row {
                Text(fam.displayName)
                    .font(Font(fam.font(size: 12) as CTFont))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
        case .backgroundSwatch(let color):
            row {
                Text("Default").font(.system(size: 11)).lineLimit(1)
                Spacer(minLength: 8)
                Swatch(color: Color(nsColor: color))
                // Reserve the pencil slot so this swatch stays column-aligned
                // with the Custom row's (same trick as the Custom+ theme row).
                Color.clear.frame(width: iconSlot, height: 1)
            }
        case .backgroundCustom(let color):
            backgroundCustomRow(color)
        }
    }

    // Reserved trailing area for the edit icon, matched to the trigger box's
    // chevron area so a row's swatches line up with the selected-theme swatches.
    // The Custom+ row (which has no pencil) reserves the same width so its
    // placeholder swatches stay column-aligned with the palette rows.
    private let iconSlot: CGFloat = 16

    /// A palette row: a select button (name + swatches) plus a trailing edit icon
    /// for custom themes (built-ins reserve the same space empty, so swatches stay
    /// aligned across every row).
    private func paletteRow(_ p: Palette) -> some View {
        HStack(spacing: 0) {
            Button { item.action?() } label: {
                HStack(spacing: 0) {
                    Text(p.name).font(.system(size: 11)).lineLimit(1)
                    Spacer(minLength: 8)
                    SwatchTrio(slots: p.slots)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(item.selected ? .isSelected : [])

            ZStack(alignment: .trailing) {
                Color.clear.frame(width: iconSlot, height: 1)   // always reserve the slot
                if let onEdit = item.onEdit {
                    Button { onEdit() } label: {
                        Image(systemName: "pencil").font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Edit \(p.name)")
                }
            }
            .foregroundStyle(Pane.muted)
        }
        .padding(.horizontal, 10)
        .frame(height: 24)
        .frame(maxWidth: .infinity)
        .background(rowBackground)
        .contentShape(Rectangle())
    }

    /// The Background dropdown's Custom row: a "Custom+" label, the picked
    /// color's swatch right-aligned like the theme rows (a blank "+" before
    /// one is picked), and a trailing pencil that reopens the color panel.
    /// Mirrors paletteRow's two-button split so the pencil is not nested
    /// inside the select button.
    private func backgroundCustomRow(_ color: NSColor?) -> some View {
        HStack(spacing: 0) {
            Button { item.action?() } label: {
                HStack(spacing: 0) {
                    Text("Custom+").font(.system(size: 11)).lineLimit(1)
                    Spacer(minLength: 8)
                    if let color {
                        Swatch(color: Color(nsColor: color))
                    } else {
                        PlusSwatch()
                    }
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Custom background")
            .accessibilityAddTraits(item.selected ? .isSelected : [])

            ZStack(alignment: .trailing) {
                Color.clear.frame(width: iconSlot, height: 1)   // always reserve the slot
                if let onEdit = item.onEdit {
                    Button { onEdit() } label: {
                        Image(systemName: "pencil").font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Edit custom background color")
                }
            }
            .foregroundStyle(Pane.muted)
        }
        .padding(.horizontal, 10)
        .frame(height: 24)
        .frame(maxWidth: .infinity)
        .background(rowBackground)
        .contentShape(Rectangle())
    }

    @ViewBuilder private func row<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        // A real Button (not a bare onTapGesture) so each row is keyboard-
        // focusable and VoiceOver announces it as a button with its selected state.
        Button { item.action?() } label: {
            HStack(spacing: 0, content: content)
                .padding(.horizontal, 10)
                .frame(height: 24)
                .frame(maxWidth: .infinity)
                .background(rowBackground)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(item.action == nil)
        .accessibilityAddTraits(item.selected ? .isSelected : [])
    }

    private var rowBackground: Color {
        if isActive { return Color.white.opacity(0.16) }
        if item.selected { return Color.white.opacity(0.10) }
        return .clear
    }

    private func emptyTrio(count: Int) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<count, id: \.self) { _ in EmptySwatch() }
            Text("|").opacity(0.35).padding(.horizontal, 2)
            ForEach(0..<count, id: \.self) { _ in EmptySwatch() }
        }
    }
}

/// Bar / Block / Underline segmented control, styled like `ModeControl`. Binds
/// the working-copy raw value so it only previews until Apply, persists on Save.
struct CursorControl: View {
    @Binding var styleRaw: String

    var body: some View {
        HStack(spacing: 0) {
            ForEach(CursorStyle.allCases, id: \.self) { style in
                let selected = styleRaw == style.rawValue
                Button { styleRaw = style.rawValue } label: {
                    Text(style.displayName)
                        .font(.system(size: 11))
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
                .accessibilityLabel(style.displayName)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .background(Pane.field)
        .overlay(Rectangle().strokeBorder(Pane.border, lineWidth: 1))
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
                Button { appearanceRaw = item.mode.rawValue } label: {
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
                .accessibilityLabel(item.label)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .background(Pane.field)
        .overlay(Rectangle().strokeBorder(Pane.border, lineWidth: 1))
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

/// A palette's light │ dark swatch trio, shown beside the name in the Theme box
/// and in every palette dropdown row. One definition so the two never drift.
struct SwatchTrio: View {
    let slots: [ColorPair]
    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(slots.enumerated()), id: \.offset) { _, slot in
                Swatch(color: Color(nsColor: slot.nsLight))
            }
            Text("|").opacity(0.35).padding(.horizontal, 2)
            ForEach(Array(slots.enumerated()), id: \.offset) { _, slot in
                Swatch(color: Color(nsColor: slot.nsDark))
            }
        }
    }
}

/// An empty 12×12 chip (outline only), a placeholder slot for a custom theme
/// that hasn't had a color chosen yet.
struct EmptySwatch: View {
    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 12, height: 12)
            .overlay(Rectangle().strokeBorder(Color(white: 0.47).opacity(0.5), lineWidth: 1))
    }
}

/// An empty swatch with a small plus: the Background dropdown's Custom state
/// before a color has been picked ("click to choose one").
struct PlusSwatch: View {
    var body: some View {
        EmptySwatch()
            .overlay(
                Image(systemName: "plus")
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(Pane.muted)
            )
    }
}

/// Sharp-cornered bordered button matching the other Settings controls.
struct SquareButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    /// Optional solid fill (e.g. red for a destructive DEFAULT action like the
    /// delete-confirmation button); nil = the neutral well.
    var tint: Color? = nil
    /// Optional colored border + matching label over the neutral well, for a
    /// non-default destructive action (e.g. the editor's Delete, which only opens
    /// a confirmation). Lighter weight than `tint` so it does not out-shout the
    /// default Save button beside it.
    var outline: Color? = nil
    /// Optional fixed width, so a row of these buttons can be made uniform (e.g.
    /// Delete and Save / Cancel sharing one size). nil = hug the label.
    var width: CGFloat? = nil

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12))
            .foregroundStyle(labelColor)
            .padding(.horizontal, 14)
            .frame(width: width, height: 26)
            .background(fill(pressed: configuration.isPressed))
            .overlay(Rectangle().strokeBorder(outline ?? tint ?? Pane.border, lineWidth: 1))
            .opacity(isEnabled ? 1.0 : 0.4)
            .contentShape(Rectangle())
    }

    private var labelColor: Color {
        if let outline { return outline }   // colored text matching the colored border
        return tint == nil ? Pane.text : .white
    }

    private func fill(pressed: Bool) -> Color {
        if let tint { return pressed ? tint.opacity(0.75) : tint }
        // outline and neutral both sit on the neutral well.
        return pressed ? Color(white: 0.40) : Pane.field
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
                SwatchTrio(slots: palette.slots)
            }
            Image(systemName: "chevron.down")
                .font(.system(size: 8))
                .opacity(0.5)
                .padding(.leading, 8)
                .rotationEffect(.degrees(isOpen ? 180 : 0))
                .animation(.easeInOut(duration: 0.15), value: isOpen)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Pane.field)
        .overlay(Rectangle().strokeBorder(Pane.border, lineWidth: 1))
    }
}

/// Editable size control (Google-Docs style): a centered number field with no
/// arrow. Clicking it opens the size dropdown with the current size highlighted;
/// typing highlights a matching size live. The typed value only takes effect on
/// Return, clicking away reverts to the current size (handled by SettingsView
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
            // field can't grab focus, and the dropdown can't pop, when the
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
        .background(Pane.field)
        .overlay(Rectangle().strokeBorder(Pane.border, lineWidth: 1))
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

/// An invisible, zero-sized color well bridging the shared `NSColorPanel` to
/// the Background working copy, reusing the CustomThemeEditor bridge pattern
/// (the panel reports picks through a real NSColorWell). Unlike that one it is
/// never clicked directly: it activates programmatically when `activation`
/// bumps (picking Custom with no color, or the pencil), and it opts out of
/// hit-testing entirely so it can never swallow clicks meant for the controls.
private struct BackgroundColorWell: NSViewRepresentable {
    @Binding var hex: String?
    /// Bump to open the panel. Compared against the coordinator's last seen
    /// value so re-renders never re-open it.
    var activation: Int
    /// What the panel shows when no custom color has been picked yet (the
    /// current mode's background, so picking starts from a familiar color).
    var initialColor: NSColor

    func makeCoordinator() -> Coordinator { Coordinator(hex: $hex) }

    func makeNSView(context: Context) -> NSColorWell {
        let well = ProgrammaticColorWell()
        well.color = hex.flatMap { NSColor(hex: $0) } ?? initialColor
        well.target = context.coordinator
        well.action = #selector(Coordinator.colorChanged(_:))
        return well
    }

    func updateNSView(_ well: NSColorWell, context: Context) {
        context.coordinator.hex = $hex
        if context.coordinator.lastActivation != activation {
            context.coordinator.lastActivation = activation
            well.color = hex.flatMap { NSColor(hex: $0) } ?? initialColor
            well.activate(true)
        }
    }

    @MainActor final class Coordinator: NSObject {
        var hex: Binding<String?>
        var lastActivation = 0
        init(hex: Binding<String?>) { self.hex = hex }

        @objc func colorChanged(_ sender: NSColorWell) {
            // Pin alpha to 1: the background persists as opaque hex, so a
            // translucent pick would disagree with what is painted and saved.
            hex.wrappedValue = sender.color.withAlphaComponent(1).hexString
        }
    }
}

/// The well behind `BackgroundColorWell`: exclusive activation configures the
/// shared panel (opaque colors only, floated above this floating window, same
/// as the Custom Theme swatches), and `hitTest` returns nil because this well
/// is only ever activated programmatically.
private final class ProgrammaticColorWell: NSColorWell {
    override func activate(_ exclusive: Bool) {
        super.activate(true)
        NSColorPanel.shared.showsAlpha = false
        NSColorPanel.shared.level = .floating
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Wraps a control with a small uppercase caption above it, always visible.
struct LabeledField<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        content
            .overlay(alignment: .topLeading) {
                Text(label.uppercased())
                    .font(.system(size: 9))
                    .tracking(0.6)
                    .foregroundStyle(Pane.muted)
                    .opacity(0.55)
                    .offset(y: -14)
                    .allowsHitTesting(false)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(label)
    }
}
