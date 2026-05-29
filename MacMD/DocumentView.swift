import SwiftUI

struct DocumentView: View {
    @Binding var document: MarkdownDocument
    @AppStorage(FontSize.key) private var fontSize = Double(FontSize.standard)

    var body: some View {
        MarkdownTextView(text: $document.text, fontSize: CGFloat(fontSize))
            .frame(minWidth: 520, idealWidth: 760, minHeight: 400, idealHeight: 680)
            .background(Color(nsColor: .textBackgroundColor))
    }
}
