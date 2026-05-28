import SwiftUI

struct DocumentView: View {
    @Binding var document: MarkdownDocument

    var body: some View {
        MarkdownTextView(text: $document.text)
            .frame(minWidth: 520, idealWidth: 760, minHeight: 400, idealHeight: 680)
            .background(Color(nsColor: .textBackgroundColor))
    }
}
