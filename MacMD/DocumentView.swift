import SwiftUI

struct DocumentView: View {
    @Binding var document: MarkdownDocument
    @AppStorage(FontSize.key) private var fontSize = Double(FontSize.standard)
    @AppStorage(ThemeSettings.schemeKey) private var schemeRaw = Coloring.off.rawValue
    @AppStorage(ThemeSettings.themeIdKey) private var themeId = ColorTheming.defaultStandardId
    @AppStorage(ThemeSettings.appearanceKey) private var appearanceRaw = AppAppearance.system.rawValue
    @AppStorage(ThemeSettings.customsKey) private var customsData = Data()

    private var coloring: Coloring { Coloring(rawValue: schemeRaw) ?? .off }
    private var appearance: AppAppearance { AppAppearance(rawValue: appearanceRaw) ?? .system }
    private var palette: Palette? {
        ThemeSettings.resolvePalette(coloring: coloring,
                                     themeId: themeId,
                                     customs: ThemeSettings.decodeCustoms(customsData))
    }

    var body: some View {
        MarkdownTextView(text: $document.text,
                         fontSize: CGFloat(fontSize),
                         coloring: coloring,
                         palette: palette,
                         appearance: appearance)
            .frame(minWidth: 520, idealWidth: 760, minHeight: 400, idealHeight: 680)
            .background(Color(nsColor: .textBackgroundColor))
    }
}
