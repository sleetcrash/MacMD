import SwiftUI

struct DocumentView: View {
    @Binding var document: MarkdownDocument
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

    /// The fixed editor background when Custom is active, else nil (Default
    /// keeps the appearance-driven `.textBackgroundColor`).
    private var customBackground: NSColor? {
        EditorBackground.customColor(mode: theme.backgroundMode, hex: theme.customBackgroundHex)
    }

    var body: some View {
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
                             cursorBlink: theme.cursorBlink)
                .frame(minWidth: 520, idealWidth: 760, minHeight: 400, idealHeight: 680)
                .background(Color(nsColor: customBackground ?? .textBackgroundColor))
            if showWordCount {
                WordCountBar(text: document.text)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: WordCountPref.didChange)) { _ in
            showWordCount = WordCountPref.isOn
        }
    }
}
