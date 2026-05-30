import SwiftUI

struct DocumentView: View {
    @Binding var document: MarkdownDocument
    @EnvironmentObject private var theme: ThemeController
    @AppStorage(ThemeSettings.appearanceKey) private var appearanceRaw = AppAppearance.system.rawValue
    @AppStorage(ThemeSettings.customsKey) private var customsData = Data()

    private var appearance: AppAppearance { AppAppearance(rawValue: appearanceRaw) ?? .system }
    private var palette: Palette? {
        ThemeSettings.resolvePalette(coloring: theme.coloring,
                                     themeId: theme.themeId,
                                     customs: ThemeSettings.decodeCustoms(customsData))
    }

    var body: some View {
        MarkdownTextView(text: $document.text,
                         fontSize: CGFloat(theme.fontSize),
                         coloring: theme.coloring,
                         palette: palette,
                         appearance: appearance)
            .frame(minWidth: 520, idealWidth: 760, minHeight: 400, idealHeight: 680)
            .background(Color(nsColor: .textBackgroundColor))
    }
}
