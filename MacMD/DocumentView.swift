import SwiftUI

struct DocumentView: View {
    @Binding var document: MarkdownDocument
    @EnvironmentObject private var theme: ThemeController
    @AppStorage(ThemeSettings.customsKey) private var customsData = Data()

    private var palette: Palette? {
        // Resolve against the freshly-persisted customs read straight from
        // UserDefaults, not this window's @AppStorage copy: for a DocumentGroup
        // scene that copy can lag a custom just saved in the Appearance/Custom
        // window, which made applying a brand-new custom fall back to a preset
        // until relaunch. Touching `customsData` keeps this view re-rendering when
        // @AppStorage *does* observe a change (e.g. editing the applied theme).
        _ = customsData
        return ThemeSettings.resolvePalette(coloring: theme.coloring,
                                            themeId: theme.themeId,
                                            customs: ThemeSettings.savedCustoms())
    }

    var body: some View {
        MarkdownTextView(text: $document.text,
                         fontSize: CGFloat(theme.fontSize),
                         coloring: theme.coloring,
                         palette: palette,
                         appearance: theme.appearance)
            .frame(minWidth: 520, idealWidth: 760, minHeight: 400, idealHeight: 680)
            .background(Color(nsColor: .textBackgroundColor))
    }
}
