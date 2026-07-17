import SwiftUI
import AppKit

/// A document window's ideal size, widened when the preview pane is showing so
/// the split opens with room for both panes. Only an ideal: macOS's remembered
/// window size wins once one exists (the New Windows setting that used to
/// override it resized whole tab groups and was removed in 2.2). Pure so it
/// can be unit tested.
enum DocumentLayout {
    static let baseSize = CGSize(width: 760, height: 680)

    static func idealSize(previewVisible: Bool) -> CGSize {
        CGSize(width: previewVisible ? baseSize.width * 1.7 : baseSize.width,
               height: baseSize.height)
    }
}

extension FocusedValues {
    var exportMarkdown: String? {
        get { self[DocumentView.ExportMarkdownKey.self] }
        set { self[DocumentView.ExportMarkdownKey.self] = newValue }
    }
}

struct DocumentView: View {
    @Binding var document: MarkdownDocument

    /// Carries the focused document's markdown to the app-level menu commands.
    struct ExportMarkdownKey: FocusedValueKey {
        typealias Value = String
    }
    /// The folder of the file being edited (nil for a new Untitled document),
    /// threaded from the DocumentGroup configuration so the preview can serve
    /// path-validated local images. `MarkdownDocument` itself carries no URL.
    var documentDirectory: URL? = nil
    @EnvironmentObject private var theme: ThemeController
    @AppStorage(ThemeSettings.customThemesKey) private var customThemesData = Data()

    /// The full theme for the current selection, resolved against the customs
    /// read straight from UserDefaults (not this window's @AppStorage copy): for
    /// a DocumentGroup scene that copy can lag a custom just saved in the
    /// Settings/Custom window, which made applying a brand-new custom fall back
    /// until relaunch. Touching `customThemesData` keeps this view re-rendering
    /// when @AppStorage *does* observe a change (e.g. editing the applied theme).
    private var resolvedTheme: Palette {
        _ = customThemesData
        return theme.resolvedTheme
    }
    /// The selection's palette, or nil under a scheme-off theme so headings use
    /// the label color (exactly like the old Default scheme).
    private var palette: Palette? {
        resolvedTheme.scheme == .off ? nil : resolvedTheme
    }

    @State private var showWordCount = WordCountPref.isOn
    @State private var showToolbar = ToolbarPref.isOn
    @State private var toolbarAutoHides = ToolbarAutoHidePref.isOn
    /// Whether the auto-hidden toolbar is currently slid in (pointer at the
    /// top of the document or on the strip itself).
    @State private var toolbarRevealed = false
    /// Live pointer state for the reveal zone and the strip. The hide task
    /// re-checks these at fire time: the zone (12pt) sits inside the taller
    /// strip (26pt), so drifting from the zone onto a button exits the zone
    /// with no fresh strip hover event, and an unconditional hide would slide
    /// the toolbar out from under the pointer.
    @State private var zoneHovered = false
    @State private var stripHovered = false
    /// Pending slide-out; cancelled whenever the pointer re-enters.
    @State private var toolbarHideTask: Task<Void, Never>?
    @State private var paneMode = PaneModePref.mode
    /// The debounced document text handed to the preview, so it does not
    /// re-render on every keystroke.
    @State private var debouncedText = ""
    /// Direct editor<->preview scroll channel; a reference type in @State so it
    /// survives re-renders while scroll ticks never touch SwiftUI state.
    @State private var syncBridge = ScrollSyncBridge()

    /// Follows the window's live appearance so a preset background under
    /// System mode flips with the OS (the environment read is what triggers
    /// the re-render; resolvesDark alone would go stale).
    @Environment(\.colorScheme) private var colorScheme

    /// The appearance the theme forces: a static theme's luminance, or the Mode
    /// for a dynamic theme (System resolving against the live OS appearance).
    private var effectiveAppearance: AppAppearance {
        EditorBackground.effectiveAppearance(background: resolvedTheme.background,
                                             isStatic: resolvedTheme.isStatic,
                                             appearance: theme.appearance)
    }

    /// The fixed editor background the theme paints, else nil (the default pair
    /// keeps the appearance-driven `.textBackgroundColor`).
    private var customBackground: NSColor? {
        let dark = effectiveAppearance == .system ? colorScheme == .dark : effectiveAppearance == .dark
        return EditorBackground.activeColor(background: resolvedTheme.background, dark: dark)
    }

    var body: some View {
        VStack(spacing: 0) {
            if showToolbar && !toolbarAutoHides {
                toolbarStrip(overlaid: false)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            HSplitView {
                if paneMode != .preview {
                    editorPane
                        .frame(minWidth: 360, idealWidth: DocumentLayout.baseSize.width)
                }
                if paneMode != .editor {
                    PreviewWebView(text: debouncedText, theme: theme,
                                   syncBridge: paneMode == .split ? syncBridge : nil,
                                   documentDirectory: documentDirectory)
                        .frame(minWidth: 320, idealWidth: DocumentLayout.baseSize.width * 0.7)
                }
            }
            // The auto-hiding toolbar overlays the panes (the macOS menu-bar
            // hiding model): a thin hover zone at the top slides it in, and it
            // slides back out when the pointer leaves it.
            .overlay(alignment: .top) {
                if showToolbar && toolbarAutoHides {
                    ZStack(alignment: .top) {
                        HoverRevealZone { inside in
                            zoneHovered = inside
                            if inside { revealToolbar() } else { scheduleToolbarHide() }
                        }
                        .frame(height: 12)
                        if toolbarRevealed {
                            toolbarStrip(overlaid: true)
                                .onHover { inside in
                                    stripHovered = inside
                                    if inside { revealToolbar() } else { scheduleToolbarHide() }
                                }
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                }
            }
        }
        .frame(minWidth: paneMode == .split ? 700 : 520,
               idealWidth: DocumentLayout.idealSize(previewVisible: paneMode == .split).width,
               minHeight: 400, idealHeight: DocumentLayout.baseSize.height)
        .task(id: document.text) {
            // Debounce the preview render (~200 ms) so typing stays smooth; the
            // markdown render itself runs in the web process, off the main thread.
            try? await Task.sleep(nanoseconds: 200_000_000)
            if !Task.isCancelled { debouncedText = document.text }
        }
        .onReceive(NotificationCenter.default.publisher(for: WordCountPref.didChange)) { _ in
            showWordCount = WordCountPref.isOn
        }
        .onReceive(NotificationCenter.default.publisher(for: PaneModePref.didChange)) { _ in
            paneMode = PaneModePref.mode
        }
        .onReceive(NotificationCenter.default.publisher(for: ToolbarPref.didChange)) { _ in
            withAnimation(.easeInOut(duration: 0.2)) { showToolbar = ToolbarPref.isOn }
        }
        .onReceive(NotificationCenter.default.publisher(for: ToolbarAutoHidePref.didChange)) { _ in
            // Removing the strip mid-hover delivers no exit event, so clear
            // the hover flags here or a stale true would block future hides.
            zoneHovered = false
            stripHovered = false
            withAnimation(.easeInOut(duration: 0.2)) {
                toolbarAutoHides = ToolbarAutoHidePref.isOn
                toolbarRevealed = false
            }
        }
        // Menu commands (Export to HTML/PDF) read the document through this,
        // not through the editor view, so they keep working in preview-only
        // layout where no editor exists.
        .focusedSceneValue(\.exportMarkdown, document.text)
    }

    /// The format toolbar wired to this document: pane picker bound to
    /// PaneModePref (kept in sync with the View menu) and one-click copy of
    /// the markdown source.
    private func toolbarStrip(overlaid: Bool) -> some View {
        EditorToolbarStrip(formatEnabled: paneMode != .preview,
                           paneMode: Binding(
                               get: { paneMode },
                               set: { PaneModePref.set($0) }
                           ),
                           onCopy: {
                               let pb = NSPasteboard.general
                               pb.clearContents()
                               pb.setString(document.text, forType: .string)
                           },
                           overlaid: overlaid)
    }

    /// Slide the auto-hidden toolbar in and cancel any pending slide-out.
    private func revealToolbar() {
        toolbarHideTask?.cancel()
        toolbarHideTask = nil
        withAnimation(.easeInOut(duration: 0.2)) { toolbarRevealed = true }
    }

    /// Slide the toolbar out after a short grace period, so crossing the gap
    /// between the hover zone and the strip does not flicker it away. The
    /// fire-time hover re-check covers the zone-exit-onto-a-button path,
    /// where no fresh enter event arrives to cancel the pending hide.
    private func scheduleToolbarHide() {
        toolbarHideTask?.cancel()
        toolbarHideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled, !zoneHovered, !stripHovered else { return }
            withAnimation(.easeInOut(duration: 0.2)) { toolbarRevealed = false }
        }
    }

    private var editorPane: some View {
        // The word-count tab overlays the editor's bottom-left corner instead of
        // occupying a full-width bar row.
        ZStack(alignment: .bottomLeading) {
            MarkdownTextView(text: $document.text,
                             fontSize: CGFloat(theme.fontSize),
                             fontFamily: FontFamily.resolve(id: theme.fontFamilyId),
                             coloring: resolvedTheme.scheme,
                             palette: palette,
                             // A static theme owns the look: its luminance (not
                             // the Mode) decides the forced appearance, so body
                             // text and heading variants stay readable.
                             appearance: effectiveAppearance,
                             customBackground: customBackground,
                             cursorStyle: theme.cursorStyle,
                             cursorBlink: theme.cursorBlink,
                             cursorColorHex: theme.cursorColorHex,
                             // Only track the top line in split layout (the one
                             // case both panes are visible), so other layouts
                             // cost no per-scroll work.
                             onTopVisibleLine: paneMode == .split
                                 ? { [syncBridge] in syncBridge.editorScrolled(toTopLine: $0) }
                                 : nil,
                             syncBridge: paneMode == .split ? syncBridge : nil)
                .background(Color(nsColor: customBackground ?? .textBackgroundColor))
            if showWordCount {
                WordCountBar(text: document.text)
                    .padding(.leading, -1)
                    .padding(.bottom, -1)
            }
        }
    }
}
