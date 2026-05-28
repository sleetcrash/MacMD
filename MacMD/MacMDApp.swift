import SwiftUI

@main
struct MacMDApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: MarkdownDocument()) { file in
            DocumentView(document: file.$document)
        }
        .commands {
            CommandGroup(replacing: .help) { }
        }
    }
}
