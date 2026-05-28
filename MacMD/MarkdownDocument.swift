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
        self.text = try Self.decode(data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Self.encode(text))
    }

    static func decode(_ data: Data) throws -> String {
        guard var s = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        if s.first == "\u{FEFF}" {
            s.removeFirst()
        }
        return s
    }

    static func encode(_ text: String) -> Data {
        guard !text.isEmpty else { return Data() }
        if text.last == "\n" {
            return Data(text.utf8)
        }
        var output = text
        output.append("\n")
        return Data(output.utf8)
    }
}
