import SwiftUI
import AppKit

/// New-document ideal window size, widened when the preview pane is showing so
/// the split opens with room for both panes. Pure so it can be unit tested.
enum DocumentLayout {
    static func idealSize(previewVisible: Bool) -> CGSize {
        let base = CGFloat(NewWindowSize.width)
        let width = previewVisible ? min(base * 1.7, CGFloat(NewWindowSize.maxWidth)) : base
        return CGSize(width: width, height: CGFloat(NewWindowSize.height))
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
    /// True for a brand-new Untitled document; sizes its window to the
    /// preferred New Windows size (reopened files keep their frames).
    var isNewDocument: Bool = false

    /// Carries the focused document's markdown to the app-level menu commands.
    struct ExportMarkdownKey: FocusedValueKey {
        typealias Value = String
    }
    /// The folder of the file being edited (nil for a new Untitled document),
    /// threaded from the DocumentGroup configuration so the preview can serve
    /// path-validated local images. `MarkdownDocument` itself carries no URL.
    var documentDirectory: URL? = nil
    @EnvironmentObject private var theme: ThemeController
    @AppStorage(ThemeSettings.customsKey) private var customsData = Data()

    private var palette: Palette? {
        // Resolve against the freshly-persisted customs read straight from
        // UserDefaults, not this window's @AppStorage copy: for a DocumentGroup
        // scene that copy can lag a custom just saved in the Settings/Custom
        // window, which made applying a brand-new custom fall back to a preset
        // until relaunch. Touching `customsData` keeps this view re-rendering when
        // @AppStorage *does* observe a change (e.g. editing the applied theme).
        _ = customsData
        return ThemeSettings.resolvePalette(coloring: theme.coloring,
                                            themeId: theme.themeId,
                                            customs: ThemeSettings.savedCustoms())
    }

    @State private var showWordCount = WordCountPref.isOn
    @State private var showToolbar = ToolbarPref.isOn
    @State private var toolbarAutoHides = ToolbarAutoHidePref.isOn
    /// Whether the auto-hidden toolbar is currently slid in (pointer at the
    /// top of the document or on the strip itself).
    @State private var toolbarRevealed = false
    /// Pending slide-out; cancelled whenever the pointer re-enters.
    @State private var toolbarHideTask: Task<Void, Never>?
    @State private var paneMode = PaneModePref.mode
    /// The debounced document text handed to the preview, so it does not
    /// re-render on every keystroke.
    @State private var debouncedText = ""
    /// Direct editor<->preview scroll channel; a reference type in @State so it
    /// survives re-renders while scroll ticks never touch SwiftUI state.
    @State private var syncBridge = ScrollSyncBridge()

    /// The fixed editor background when Custom is active, else nil (Default
    /// keeps the appearance-driven `.textBackgroundColor`).
    private var customBackground: NSColor? {
        EditorBackground.customColor(mode: theme.backgroundMode, hex: theme.customBackgroundHex)
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
                        .frame(minWidth: 360, idealWidth: CGFloat(NewWindowSize.width))
                }
                if paneMode != .editor {
                    PreviewWebView(text: debouncedText, theme: theme,
                                   syncBridge: paneMode == .split ? syncBridge : nil,
                                   documentDirectory: documentDirectory)
                        .frame(minWidth: 320, idealWidth: CGFloat(NewWindowSize.width) * 0.7)
                }
            }
            // The auto-hiding toolbar overlays the panes (the macOS menu-bar
            // hiding model): a thin hover zone at the top slides it in, and it
            // slides back out when the pointer leaves it.
            .overlay(alignment: .top) {
                if showToolbar && toolbarAutoHides {
                    ZStack(alignment: .top) {
                        HoverRevealZone { inside in
                            if inside { revealToolbar() } else { scheduleToolbarHide() }
                        }
                        .frame(height: 12)
                        if toolbarRevealed {
                            toolbarStrip(overlaid: true)
                                .onHover { inside in
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
               minHeight: 400, idealHeight: CGFloat(NewWindowSize.height))
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
    /// between the hover zone and the strip does not flicker it away.
    private func scheduleToolbarHide() {
        toolbarHideTask?.cancel()
        toolbarHideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
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
                             coloring: theme.coloring,
                             palette: palette,
                             // A custom background owns the look: its luminance
                             // (not the Mode) decides the forced appearance, so
                             // body text and heading variants stay readable.
                             appearance: EditorBackground.effectiveAppearance(mode: theme.backgroundMode,
                                                                              hex: theme.customBackgroundHex,
                                                                              appearance: theme.appearance),
                             customBackground: customBackground,
                             cursorStyle: theme.cursorStyle,
                             cursorBlink: theme.cursorBlink,
                             sizeWindowToPreference: isNewDocument,
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
