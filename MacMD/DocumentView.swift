import SwiftUI

/// New-document ideal window size, widened when the preview pane is showing so
/// the split opens with room for both panes. Pure so it can be unit tested.
enum DocumentLayout {
    static func idealSize(previewVisible: Bool) -> CGSize {
        let base = CGFloat(NewWindowSize.width)
        let width = previewVisible ? min(base * 1.7, CGFloat(NewWindowSize.maxWidth)) : base
        return CGSize(width: width, height: CGFloat(NewWindowSize.height))
    }
}

struct DocumentView: View {
    @Binding var document: MarkdownDocument
    /// True for a brand-new Untitled document; sizes its window to the
    /// preferred New Windows size (reopened files keep their frames).
    var isNewDocument: Bool = false
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
    @State private var showPreview = PreviewPref.isVisible
    /// The debounced document text handed to the preview, so it does not
    /// re-render on every keystroke.
    @State private var debouncedText = ""
    @State private var topLine: Int?

    /// The fixed editor background when Custom is active, else nil (Default
    /// keeps the appearance-driven `.textBackgroundColor`).
    private var customBackground: NSColor? {
        EditorBackground.customColor(mode: theme.backgroundMode, hex: theme.customBackgroundHex)
    }

    var body: some View {
        HSplitView {
            editorPane
                .frame(minWidth: 360, idealWidth: CGFloat(NewWindowSize.width))
            if showPreview {
                PreviewWebView(text: debouncedText, theme: theme,
                               topVisibleLine: topLine, documentDirectory: documentDirectory)
                    .frame(minWidth: 320, idealWidth: CGFloat(NewWindowSize.width) * 0.7)
            }
        }
        .frame(minWidth: showPreview ? 700 : 520,
               idealWidth: DocumentLayout.idealSize(previewVisible: showPreview).width,
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
        .onReceive(NotificationCenter.default.publisher(for: PreviewPref.didChange)) { _ in
            showPreview = PreviewPref.isVisible
        }
    }

    private var editorPane: some View {
        VStack(spacing: 0) {
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
                             // Only track the top line while the preview is showing,
                             // so a hidden preview costs no per-scroll work.
                             onTopVisibleLine: showPreview ? { topLine = $0 } : nil)
                .background(Color(nsColor: customBackground ?? .textBackgroundColor))
            if showWordCount {
                WordCountBar(text: document.text)
            }
        }
    }
}
