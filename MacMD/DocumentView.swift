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
            if showToolbar {
                EditorToolbarStrip(formatEnabled: paneMode != .preview)
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
            .overlay(alignment: .topTrailing) { layoutToggle }
        }
        .frame(minWidth: paneMode == .split ? 700 : 520,
               idealWidth: DocumentLayout.idealSize(previewVisible: paneMode == .split).width,
               minHeight: 400, idealHeight: CGFloat(NewWindowSize.height))
        .toolbar {
            // Always-visible window chrome: collapse/restore the format toolbar,
            // and one-click copy of the markdown source. The pane-layout control
            // floats in the document's top-right corner.
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    ToolbarPref.set(!showToolbar)
                } label: {
                    Label("Toggle Format Toolbar", systemImage: "textformat")
                }
                .help(showToolbar ? "Hide the format toolbar" : "Show the format toolbar")
                Button {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(document.text, forType: .string)
                } label: {
                    Label("Copy Text", systemImage: "doc.on.doc")
                }
                .help("Copy the document text")
            }
        }
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
        // Menu commands (Export to HTML/PDF) read the document through this,
        // not through the editor view, so they keep working in preview-only
        // layout where no editor exists.
        .focusedSceneValue(\.exportMarkdown, document.text)
    }

    /// The compact pane-layout toggle floating in the document's top-right
    /// corner. Bound to PaneModePref, so it stays in sync with the View menu.
    private var layoutToggle: some View {
        Picker("Layout", selection: Binding(
            get: { paneMode },
            set: { PaneModePref.set($0) }
        )) {
            ForEach(PaneMode.allCases, id: \.self) { mode in
                Image(systemName: mode.systemImage)
                    .help(mode.displayName)
                    .tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .controlSize(.small)
        .padding(8)
        .help("Editor, split, or preview layout")
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
