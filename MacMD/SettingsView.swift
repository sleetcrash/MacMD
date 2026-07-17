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
    @AppStorage(ThemeSettings.customThemesKey) private var customsData = Data()

    // Working copy, edits here don't reach the document until Apply/Save.
    @State private var wcSelectedTheme = "default"
    @State private var wcFontSize = Double(FontSize.standard)
    @State private var wcAppearanceRaw = AppAppearance.system.rawValue
    @State private var wcFontFamilyId = FontFamily.default.id
    @State private var wcCursorStyleRaw = CursorStyle.bar.rawValue
    @State private var wcCursorBlink = true
    /// nil = the system accent (the default caret color).
    @State private var wcCursorColorHex: String?
    /// Bump to open the shared color panel on the cursor-color well.
    @State private var cursorColorPickerActivation = 0
    @State private var sizeText = ""

    // The Editing tab. Its controls take effect immediately (standard macOS
    // settings behavior), unlike the Appearance tab's transactional Apply/Save.
    @State private var tab: SettingsTab = .appearance
    @AppStorage(SpellingPref.spellingKey) private var checkSpelling = true
    @AppStorage(SpellingPref.grammarKey) private var checkGrammar = false
    @AppStorage(WordCountPref.key) private var showWordCount = false
    @AppStorage(ToolbarPref.key) private var showToolbar = true
    @AppStorage(ToolbarAutoHidePref.key) private var toolbarAutoHides = true

    // Which dropdown (if any) is open, and the on-screen frame of each trigger
    // box so the in-window dropdown can sit flush beneath it.
    @State private var openMenu: MenuField?
    @State private var fieldFrames: [MenuField: CGRect] = [:]

    static let space = "settingsMenu"
    private let wideWidth: CGFloat = 225
    // The right column width: the Size field and its empty siblings share it so
    // the right column stays uniform.
    private let segWidth: CGFloat = 110
    private let rowHeight: CGFloat = 32

    private var wcAppearance: AppAppearance { AppAppearance(rawValue: wcAppearanceRaw) ?? .system }
    private var customs: [Palette] { ThemeSettings.decodeCustoms(customsData) }
    /// The working selection resolved to a full theme (name, scheme, slots,
    /// background, kind): what the Theme box and preview render.
    private var wcResolvedTheme: Palette {
        ThemeSettings.resolveTheme(id: wcSelectedTheme, customs: customs)
    }
    private var wcFontFamily: FontFamily { FontFamily.resolve(id: wcFontFamilyId) }
    /// The background pair + kind the preview paints and the Mode inertness
    /// reads: while a draft is being edited, its seed theme's; otherwise the
    /// resolved working theme's. A brand-new draft has no seed, so it is dynamic.
    private var previewBackground: (pair: ColorPair, isStatic: Bool) {
        if customDraft.active {
            if let id = customDraft.editingId, let t = customs.first(where: { $0.id == id }) {
                return (t.background, t.isStatic)
            }
            return (EditorBackground.defaultPair, false)
        }
        return (wcResolvedTheme.background, wcResolvedTheme.isStatic)
    }
    /// The Mode segments go inert while the previewed look is static (its
    /// appearance is set by the theme's luminance, not the Mode).
    private var modeInert: Bool { previewBackground.isStatic }
    // Apply lights up when the selection differs from what the editor is
    // currently showing (the applied/effective state), so you can always apply
    // your choice, even if it equals the saved value. Save lights up when the
    // selection differs from the persisted (saved) value.
    private var applyDirty: Bool {
        wcSelectedTheme != theme.themeId
        || wcFontSize != theme.fontSize
        || wcAppearance != theme.appearance
        || wcFontFamilyId != theme.fontFamilyId
        || wcCursorStyleRaw != theme.cursorStyle.rawValue
        || wcCursorBlink != theme.cursorBlink
        || wcCursorColorHex != theme.cursorColorHex
    }
    private var saveDirty: Bool {
        wcSelectedTheme != theme.savedThemeId
        || wcFontSize != theme.savedFontSize
        || wcAppearanceRaw != theme.savedAppearance.rawValue
        || wcFontFamilyId != theme.savedFontFamilyId
        || wcCursorStyleRaw != theme.savedCursorStyle.rawValue
        || wcCursorBlink != theme.savedCursorBlink
        || wcCursorColorHex != theme.savedCursorColor
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
        // the cursor-color working copy. Mounted on the window root (not the
        // transient dropdown) so the panel keeps feeding color changes after the
        // dropdown closes. Opened programmatically via cursorColorPickerActivation.
        .background(SettingsColorWell(hex: $wcCursorColorHex,
                                      activation: cursorColorPickerActivation,
                                      initialColor: .controlAccentColor)
            .frame(width: 0, height: 0))
        // macOS frame autosave can restore this auxiliary window partway off the
        // screen edge; pull it back fully on screen on open (a dragged on-screen
        // position is left untouched).
        .background(KeepOnScreen())
        .onAppear { syncFromSaved(); reconcileThemeId() }
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
            if let id { wcSelectedTheme = id }
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
        // repoint the working copy to Default so the Theme box and dropdown
        // selection stay truthful (and Save can't persist a dead id).
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
                LabeledField(label: "Theme") {
                    themeBox.frame(width: wideWidth, height: rowHeight)
                }
                Color.clear.frame(width: segWidth, height: rowHeight)
            }
            HStack(spacing: 14) {
                // A static theme sets the appearance from its own luminance, so
                // the Mode segments go inert and the caption says so.
                LabeledField(label: modeInert ? "Set by theme" : "Mode") {
                    ModeControl(appearanceRaw: $wcAppearanceRaw)
                        .frame(width: wideWidth, height: rowHeight)
                        .disabled(modeInert)
                        .opacity(modeInert ? 0.45 : 1)
                }
                Color.clear.frame(width: segWidth, height: rowHeight)
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
                LabeledField(label: "Color") {
                    cursorColorBox.frame(width: segWidth, height: rowHeight)
                }
            }
            Toggle("Blink", isOn: $wcCursorBlink)
                .toggleStyle(.checkbox)
                .font(.system(size: 11))
                .frame(height: 20)
                .padding(.top, -8)
            ThemePreview(coloring: customDraft.active ? customDraft.scheme : wcResolvedTheme.scheme,
                         palette: customDraft.active ? customDraft.palette
                                                     : (wcResolvedTheme.scheme == .off ? nil : wcResolvedTheme),
                         appearance: wcAppearance, fontSize: CGFloat(wcFontSize),
                         family: wcFontFamily,
                         background: previewBackground.pair, isStatic: previewBackground.isStatic)
                .frame(maxWidth: .infinity)
            HStack(spacing: 10) {
                // No Close button: the title-bar close control and Escape already
                // revert any unsaved Apply and dismiss (via onDisappear), matching
                // the Custom Theme window. Apply and Save sit at the trailing edge.
                Spacer()
                Button("Apply") {
                    theme.apply(themeId: wcSelectedTheme, fontSize: wcFontSize, appearance: wcAppearance)
                    theme.applyFontFamily(wcFontFamilyId)
                    theme.applyCursor(style: CursorStyle(rawValue: wcCursorStyleRaw) ?? .bar, blink: wcCursorBlink)
                    theme.applyCursorColor(wcCursorColorHex)
                }
                    .buttonStyle(SquareButtonStyle())
                    .disabled(!applyDirty || draftUncommitted)
                Button("Save") {
                    theme.save(themeId: wcSelectedTheme, fontSize: wcFontSize, appearance: wcAppearance)
                    theme.saveFontFamily(wcFontFamilyId)
                    theme.saveCursor(style: CursorStyle(rawValue: wcCursorStyleRaw) ?? .bar, blink: wcCursorBlink)
                    theme.saveCursorColor(wcCursorColorHex)
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
                caption("Toolbar")
                Toggle("Show toolbar", isOn: Binding(
                    get: { showToolbar },
                    set: { ToolbarPref.set($0) }
                ))
                .toggleStyle(.checkbox)
                .font(.system(size: 12))
                Toggle("Automatically hide and show the toolbar", isOn: Binding(
                    get: { toolbarAutoHides },
                    set: { ToolbarAutoHidePref.set($0) }
                ))
                .toggleStyle(.checkbox)
                .font(.system(size: 12))
                .disabled(!showToolbar)
            }
            VStack(alignment: .leading, spacing: 10) {
                caption("Word count")
                Toggle("Show word count", isOn: Binding(
                    get: { showWordCount },
                    set: { WordCountPref.set($0) }
                ))
                .toggleStyle(.checkbox)
                .font(.system(size: 12))
            }
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

    // MARK: - Trigger boxes

    private var themeBox: some View {
        Button { toggle(.theme) } label: {
            ThemeBoxLabel(theme: wcResolvedTheme, isOpen: openMenu == .theme)
        }
        .buttonStyle(.plain)
        .reportsFrame(.theme)
    }

    /// The Cursor Color trigger: Default (the system accent) or the picked
    /// fixed color, swatch right-aligned against the chevron like Background.
    private var cursorColorBox: some View {
        Button { toggle(.cursorColor) } label: {
            HStack(spacing: 0) {
                Text(wcCursorColorHex == nil ? "Default" : "Customize")
                    .font(.system(size: 11))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Swatch(color: Color(nsColor: wcCursorColorHex.flatMap { NSColor(hex: $0) } ?? .controlAccentColor))
                Image(systemName: "chevron.down").font(.system(size: 8)).opacity(0.5)
                    .padding(.leading, 8)
                    .rotationEffect(.degrees(openMenu == .cursorColor ? 180 : 0))
                    .animation(.easeInOut(duration: 0.15), value: openMenu == .cursorColor)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Pane.field)
            .overlay(Rectangle().strokeBorder(Pane.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Cursor color")
        .reportsFrame(.cursorColor)
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
                .offset(x: frame.maxX - frame.width, y: frame.maxY)
        }
    }

    private func items(for field: MenuField) -> [DropdownItem] {
        switch field {
        case .theme:
            // (1) Customize create row (plus glyph in the trailing icon slot).
            var rows = [DropdownItem(id: "custom.plus", kind: .customPlus, action: {
                openMenu = nil
                customDraft.begin(scheme: .unified)
                openWindow(id: CustomThemeScene.id)
            })]
            // (2) Custom header + saved customs (pencil on standard/unified only).
            if !customs.isEmpty {
                rows.append(DropdownItem(id: "hdr.custom", kind: .header("Custom")))
                rows.append(contentsOf: customs.map { themeRow($0, editable: $0.scheme != .off) })
            }
            // (3) Default, then (4) the Cream/Parchment/Gray tints (its siblings).
            rows.append(themeRow(Palette.defaultTheme, editable: false))
            rows.append(contentsOf: Palette.tintThemes.map { themeRow($0, editable: false) })
            // (5) Standard header + presets.
            rows.append(DropdownItem(id: "hdr.standard", kind: .header("Standard")))
            rows.append(contentsOf: ColorTheming.standardPresets.map { themeRow($0, editable: false) })
            // (6) Unified header + presets.
            rows.append(DropdownItem(id: "hdr.unified", kind: .header("Unified")))
            rows.append(contentsOf: ColorTheming.unifiedPresets.map { themeRow($0, editable: false) })
            return rows
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
        case .cursorColor:
            let picked = wcCursorColorHex.flatMap { NSColor(hex: $0) }
            return [
                DropdownItem(id: "cursor.default",
                             kind: .backgroundSwatch(.controlAccentColor),
                             selected: wcCursorColorHex == nil,
                             action: { pickCursorColorDefault() }),
                DropdownItem(id: "cursor.custom",
                             kind: .backgroundCustom(picked),
                             selected: wcCursorColorHex != nil,
                             action: { pickCursorColorCustom() },
                             onEdit: picked == nil ? nil : { openCursorColorPicker() }),
            ]
        }
    }

    private func toggle(_ field: MenuField) { openMenu = (openMenu == field ? nil : field) }

    private func pickTheme(_ id: String) { wcSelectedTheme = id; openMenu = nil }
    private func pickFont(_ id: String) { wcFontFamilyId = id; openMenu = nil }

    /// One Theme dropdown row for a full theme. Scheme-off themes (Default,
    /// tints, off-scheme customs) show a background pair swatch; standard and
    /// unified themes show their heading trio. An editable custom (standard or
    /// unified this task) gets a trailing pencil that reopens the builder.
    private func themeRow(_ p: Palette, editable: Bool) -> DropdownItem {
        let kind: DropdownItem.Kind = p.scheme == .off
            ? .backgroundPair(name: p.name, pair: p.background)
            : .palette(p)
        return DropdownItem(
            id: p.id, kind: kind, selected: p.id == wcSelectedTheme,
            action: { pickTheme(p.id) },
            onEdit: editable ? {
                openMenu = nil
                customDraft.beginEditing(p)
                openWindow(id: CustomThemeScene.id)
            } : nil)
    }

    /// The cursor's Default row: back to the system accent.
    private func pickCursorColorDefault() {
        wcCursorColorHex = nil
        openMenu = nil
    }

    /// The cursor's Customize row: open the panel when no color is picked yet
    /// (the first pick selects it); with one, the pencil reopens the panel.
    private func pickCursorColorCustom() {
        openMenu = nil
        if wcCursorColorHex == nil { cursorColorPickerActivation += 1 }
    }

    private func openCursorColorPicker() {
        openMenu = nil
        cursorColorPickerActivation += 1
    }

    private func pickSize(_ s: Int) {
        wcFontSize = Double(FontSize.clamp(CGFloat(s)))
        sizeText = "\(Int(wcFontSize))"
        openMenu = nil
    }

    private func syncFromSaved() {
        wcSelectedTheme = theme.savedThemeId
        wcFontSize = theme.savedFontSize
        wcAppearanceRaw = theme.savedAppearance.rawValue
        wcFontFamilyId = theme.savedFontFamilyId
        wcCursorStyleRaw = theme.savedCursorStyle.rawValue
        wcCursorBlink = theme.savedCursorBlink
        wcCursorColorHex = theme.savedCursorColor
        sizeText = "\(Int(theme.savedFontSize))"
    }

    /// If the selected theme id no longer resolves to itself (e.g. the custom it
    /// pointed at was deleted), repoint the working copy to Default, so the Theme
    /// box label and the dropdown's selected highlight match what is actually
    /// drawn (and Save can't persist a dead id).
    private func reconcileThemeId() {
        if wcResolvedTheme.id != wcSelectedTheme { wcSelectedTheme = "default" }
    }

}

// MARK: - Dropdown plumbing

/// Identifies which trigger box a dropdown belongs to.
enum MenuField: Hashable { case theme, size, font, cursorColor }

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
        case customPlus             // "Customize" + empty light | dark swatches + plus
        case header(String)         // non-selectable subheading
        case text(String)           // plain title (scheme / size)
        case fontSample(FontFamily) // family name rendered in its own face
        case backgroundSwatch(NSColor)   // a single-swatch Default row (cursor color)
        case backgroundPair(name: String, pair: ColorPair)  // Default/preset: light | dark pair
        case backgroundCustom(NSColor?)  // Background's Custom row: the picked color, or nil = blank "+"
        case backgroundSaved(hex: String, color: NSColor)  // a library swatch, removable
    }
    let id: String
    let kind: Kind
    var selected = false
    var centered = false
    var action: (() -> Void)? = nil
    // Custom palette rows only, drives the trailing pencil (edit) icon.
    var onEdit: (() -> Void)? = nil
    // Saved-background rows only, drives the trailing remove (x) icon.
    var onDelete: (() -> Void)? = nil
}

/// A seamless in-window dropdown: a flush list of rows the exact width of its
/// trigger box, sharp-edged and opaque, with no system menu chrome. It renders
/// inside the window (not a floating menu window), so it reads as attached and
/// inherits the window's light/dark Mode.
struct InlineDropdown: View {
    let items: [DropdownItem]
    /// The Theme/Font dropdowns handle arrow-key / Return nav; the Size dropdown
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
                let selected = items.firstIndex(where: { $0.selected })
                activeIndex = selected ?? Self.nextSelectable(from: nil, step: 1, items: items)
                // Scroll the selected row into view on open (matching move()'s
                // scrollTo), so a selection far down a scrolling list is visible.
                if let selected {
                    DispatchQueue.main.async { proxy.scrollTo(items[selected].id, anchor: .center) }
                }
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
            DispatchQueue.main.async {
                MainActor.assumeIsolated { context.coordinator.attach(from: nsView) }
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(onScroll) }

    @MainActor
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
        case .customPlus:
            row {
                Text("Customize").font(.system(size: 11))
                Spacer(minLength: 8)
                emptyTrio(count: 3)
                // The create glyph sits in the same trailing slot the palette
                // rows give the pencil, so swatches stay column-aligned and
                // plus reads as this row's counterpart to edit.
                ZStack(alignment: .trailing) {
                    Color.clear.frame(width: iconSlot, height: 1)
                    Image(systemName: "plus")
                        .font(.system(size: 10))
                        .foregroundStyle(Pane.muted)
                }
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
                // with the Custom row's (same trick as the Customize theme row).
                Color.clear.frame(width: iconSlot, height: 1)
            }
        case .backgroundPair(let name, let pair):
            row {
                Text(name).font(.system(size: 11)).lineLimit(1)
                Spacer(minLength: 8)
                SwatchTrio(slots: [pair])
                Color.clear.frame(width: iconSlot, height: 1)
            }
        case .backgroundCustom(let color):
            backgroundCustomRow(color)
        case .backgroundSaved(let hex, let color):
            backgroundSavedRow(hex: hex, color: color)
        }
    }

    /// A saved-library background row: the hex as its label, the swatch
    /// right-aligned, and a trailing x that removes it from the library
    /// (mirrors paletteRow's select-button + trailing-icon split).
    private func backgroundSavedRow(hex: String, color: NSColor) -> some View {
        HStack(spacing: 0) {
            Button { item.action?() } label: {
                HStack(spacing: 0) {
                    Text(hex)
                        .font(.system(size: 10, design: .monospaced))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Swatch(color: Color(nsColor: color))
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Saved background \(hex)")
            .accessibilityAddTraits(item.selected ? .isSelected : [])

            ZStack(alignment: .trailing) {
                Color.clear.frame(width: iconSlot, height: 1)
                if let onDelete = item.onDelete {
                    Button { onDelete() } label: {
                        Image(systemName: "xmark").font(.system(size: 9))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove saved background \(hex)")
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

    // Reserved trailing area for the edit icon, matched to the trigger box's
    // chevron area so a row's swatches line up with the selected-theme swatches.
    // The Customize row (whose slot holds plus) reserves the same width so its
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

    /// The Background dropdown's Customize row: the picked color's swatch
    /// right-aligned like the theme rows (an empty swatch before one is
    /// picked), and the trailing icon slot holding plus (nothing picked yet)
    /// or the pencil that reopens the color panel. Mirrors paletteRow's
    /// two-button split so the pencil is not nested inside the select button.
    private func backgroundCustomRow(_ color: NSColor?) -> some View {
        HStack(spacing: 0) {
            Button { item.action?() } label: {
                HStack(spacing: 0) {
                    Text("Customize").font(.system(size: 11)).lineLimit(1)
                    Spacer(minLength: 8)
                    if let color {
                        Swatch(color: Color(nsColor: color))
                    } else {
                        EmptySwatch()
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
                } else {
                    Image(systemName: "plus").font(.system(size: 10))
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

/// The static Theme box label: the resolved theme's name (left), its swatches
/// (right, flush to the arrow), and the dropdown arrow at the right edge. A
/// scheme-off theme (Default, tints, off customs) shows its background pair; a
/// colored theme shows its heading trio.
struct ThemeBoxLabel: View {
    let theme: Palette
    var isOpen: Bool = false

    var body: some View {
        HStack(spacing: 0) {
            Text(theme.name)
                .font(.system(size: 11))
                .lineLimit(1)
            Spacer(minLength: 8)
            SwatchTrio(slots: theme.scheme == .off ? [theme.background] : theme.slots)
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

/// An invisible, zero-sized color well bridging the shared `NSColorPanel` to a
/// hex working copy (the Background and Cursor Color pickers each mount one),
/// reusing the CustomThemeEditor bridge pattern (the panel reports picks
/// through a real NSColorWell). Unlike that one it is never clicked directly:
/// it activates programmatically when `activation` bumps (picking Custom with
/// no color, or the pencil), and it opts out of hit-testing entirely so it can
/// never swallow clicks meant for the controls.
private struct SettingsColorWell: NSViewRepresentable {
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

/// The well behind `SettingsColorWell`: exclusive activation configures the
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
