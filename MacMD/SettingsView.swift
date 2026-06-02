import SwiftUI
import AppKit

/// The Appearance window's chrome palette: semantic system colors that resolve
/// against the window's appearance. `SystemWindowAppearance` pins the window to
/// the OS appearance (like the system color picker), so these follow the OS —
/// light in Light, dark in Dark — independent of the editor Mode. (The preview
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
/// for an auxiliary `Window` scene — leaving the Pane.* semantic colors to
/// resolve against whatever appearance a document window last forced via its
/// editor Mode. SwiftUI re-runs `updateNSView` whenever the window's content
/// updates, so the pin re-asserts on every interaction. (Like the sibling
/// `PositionBesideAppearance`, the async hop covers the first pass where the view
/// isn't attached to its window yet.)
struct SystemWindowAppearance: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            let dark = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
            window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        }
    }
}

/// Pure geometry for keeping a window on screen. macOS frame autosave can
/// restore an auxiliary `Window` partway off the screen edge (the more so after
/// heavy reposition churn); this nudges a frame back fully inside `visible`
/// (a screen's `visibleFrame`, which already excludes the menu bar and Dock).
/// A frame already inside `visible` is returned unchanged, so a position the
/// user deliberately dragged to still sticks. A frame larger than the visible
/// area on an axis is pinned to that axis's leading edge — top for Y — so the
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
/// `WindowPlacement.onScreen`. Applied to the Appearance window (and reused by
/// `PositionBesideAppearance` for the Custom Theme window). Runs once per
/// attachment — a frame the user later drags somewhere on-screen is left alone.
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

    // Working copy — edits here don't reach the document until Apply/Save.
    @State private var wcSchemeRaw = Coloring.off.rawValue
    @State private var wcThemeId = ColorTheming.defaultStandardId
    @State private var wcFontSize = Double(FontSize.standard)
    @State private var wcAppearanceRaw = AppAppearance.system.rawValue
    @State private var sizeText = ""

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
    // Apply lights up when the selection differs from what the editor is
    // currently showing (the applied/effective state), so you can always apply
    // your choice — even if it equals the saved value. Save lights up when the
    // selection differs from the persisted (saved) value.
    private var applyDirty: Bool {
        wcColoring != theme.coloring
        || wcThemeId != theme.themeId
        || wcFontSize != theme.fontSize
        || wcAppearance != theme.appearance
    }
    private var saveDirty: Bool {
        wcSchemeRaw != theme.savedColoring.rawValue
        || wcThemeId != theme.savedThemeId
        || wcFontSize != theme.savedFontSize
        || wcAppearanceRaw != theme.savedAppearance.rawValue
    }
    // A new custom theme is being edited in the Custom Theme window but hasn't been
    // saved yet, so it has no committable id. The preview shows the live draft, but
    // Apply/Save here would commit the previously-selected theme — so they're
    // disabled until the draft is saved (which selects it via savedId).
    private var draftUncommitted: Bool { customDraft.active && customDraft.editingId == nil }

    var body: some View {
        ZStack(alignment: .topLeading) {
            content
            dropdownLayer
        }
        .frame(width: 354)
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
            // satellites of this window — never leave them orphaned when it closes.
            // (The builder's own onDisappear only re-focuses "Appearance" while it
            // is still visible, so this can't resurrect a closing window.)
            NSApp.windows.first { $0.title == "Custom Theme" }?.close()
            NSColorPanel.shared.close()
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
        // window the same way Close does — revert any unsaved Apply.
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
            ThemePreview(coloring: customDraft.active ? customDraft.scheme : wcColoring,
                         palette: customDraft.active ? customDraft.palette : wcPalette,
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
                    .disabled(!applyDirty || draftUncommitted)
                Button("Save") {
                    theme.save(coloring: wcColoring, themeId: wcThemeId,
                               fontSize: wcFontSize, appearance: wcAppearance)
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
        }
    }

    private func toggle(_ field: MenuField) { openMenu = (openMenu == field ? nil : field) }

    private func pickTheme(_ id: String) { wcThemeId = id; openMenu = nil }

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
    // Custom palette rows only — drives the trailing pencil (edit) icon.
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
    /// content without measuring — a measured height inside a ScrollView never
    /// settles reliably.
    static let rowHeight: CGFloat = 24
    static let headerHeight: CGFloat = 21
    /// The list must end above the window's bottom buttons (a clear gap before the
    /// window bottom). The actual cap is this ceiling snapped DOWN to a whole row
    /// (see `snappedHeight`), so the bottom visible row is never sliced in half; a
    /// taller list scrolls within it.
    static let ceiling: CGFloat = 204
    private static let scrollSpace = "dropdownScroll"

    @State private var scrollOffset: CGFloat = 0
    /// The highlighted row — driven by BOTH keyboard nav and mouse hover, so the
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
    /// nil if the offset lands on a header or outside the list — turns a single
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
                .background(GeometryReader { geo in
                    Color.clear.preference(key: ScrollOffsetKey.self,
                                           value: -geo.frame(in: .named(Self.scrollSpace)).minY)
                })
            }
            .scrollIndicators(.hidden)
            .frame(height: height)
            // Name the FIXED viewport box (applied AFTER .frame), not the
            // ScrollView's own content-anchored space. Measuring the scrolling
            // content's minY against this stationary frame makes it go negative as
            // you scroll, so ScrollOffsetKey actually changes and the thumb moves.
            // With the name on the raw ScrollView, minY read ~0 forever -> the
            // thumb was pinned at the top.
            .coordinateSpace(name: Self.scrollSpace)
            .background(Pane.field)
            // One container-level hover tracker maps the pointer to a row, instead
            // of a tracking area per row — far snappier on the 2019 Intel MBP — and
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
            .onPreferenceChange(ScrollOffsetKey.self) { scrollOffset = max(0, $0) }
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
    // deterministic. It is scoped to the Appearance window (so it never steals
    // keys from a document window) and torn down when the dropdown closes.
    private func installKeyMonitor(_ proxy: ScrollViewProxy) {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard NSApp.keyWindow?.title == "Appearance" else { return event }
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

/// Tracks the dropdown's scroll position so the custom scroll indicator can
/// follow it.
private struct ScrollOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

struct DropdownRow: View {
    let item: DropdownItem
    /// Highlighted by the parent (keyboard nav or the container-level hover
    /// tracker) — the row no longer tracks its own hover.
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
                Color.clear.frame(width: Self.iconSlot, height: 1)
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

    // Reserved trailing area for the edit icon — matched to the trigger box's
    // chevron area so a row's swatches line up with the selected-theme swatches.
    // Static so the Custom+ row (which has no pencil) can reserve the same slot
    // and stay column-aligned with the palette rows, and so the width is one
    // shared constant a test can pin.
    static let iconSlot: CGFloat = 16

    /// A palette row: a select button (name + swatches) plus a trailing edit icon
    /// for custom themes (built-ins reserve the same space empty, so swatches stay
    /// aligned across every row).
    private func paletteRow(_ p: Palette) -> some View {
        HStack(spacing: 0) {
            Button { item.action?() } label: {
                HStack(spacing: 0) {
                    Text(p.name).font(.system(size: 11)).lineLimit(1)
                    Spacer(minLength: 8)
                    swatchTrio(light: p.slots.map { Color(nsColor: $0.nsLight) },
                               dark: p.slots.map { Color(nsColor: $0.nsDark) })
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(item.selected ? .isSelected : [])

            ZStack(alignment: .trailing) {
                Color.clear.frame(width: Self.iconSlot, height: 1)   // always reserve the slot
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
    /// Optional fill (e.g. red for a destructive Delete); nil = the neutral well.
    var tint: Color? = nil

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12))
            .foregroundStyle(tint == nil ? Pane.text : .white)
            .padding(.horizontal, 14)
            .frame(height: 26)
            .background(fill(pressed: configuration.isPressed))
            .overlay(Rectangle().strokeBorder(tint ?? Pane.border, lineWidth: 1))
            .opacity(isEnabled ? 1.0 : 0.4)
            .contentShape(Rectangle())
    }

    private func fill(pressed: Bool) -> Color {
        if let tint { return pressed ? tint.opacity(0.75) : tint }
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
                    .foregroundStyle(Pane.muted)
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
