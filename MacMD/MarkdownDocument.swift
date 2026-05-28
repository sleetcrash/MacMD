import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let markdown: UTType = {
        if let t = UTType(filenameExtension: "md", conformingTo: .plainText) {
            return t
        }
        return UTType(importedAs: "net.daringfireball.markdown", conformingTo: .plainText)
    }()
}

struct MarkdownDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.markdown, .plainText]
    static let writableContentTypes: [UTType] = [.markdown, .plainText]

    var text: String

    init(text: String = "") {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        guard let s = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        self.text = s
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = Data(text.utf8)
        return FileWrapper(regularFileWithContents: data)
    }
}
