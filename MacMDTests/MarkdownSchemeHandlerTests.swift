import XCTest
import WebKit
@testable import MacMD

final class MarkdownSchemeHandlerTests: XCTestCase {

    func testImageURLContainmentRejectsEscapes() throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let docDir = tempRoot.appendingPathComponent("doc")
        try fm.createDirectory(at: docDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempRoot) }

        // A legit image inside the document folder, and a secret one level up.
        try Data("png".utf8).write(to: docDir.appendingPathComponent("local.png"))
        let secret = tempRoot.appendingPathComponent("secret.txt")
        try Data("secret".utf8).write(to: secret)

        let handler = MarkdownSchemeHandler()
        handler.documentDirectory = docDir

        // A contained image resolves inside the document directory.
        let resolved = handler.imageURL(forToken: "local.png")
        XCTAssertNotNil(resolved)
        let baseCanonical = docDir.resolvingSymlinksInPath().standardizedFileURL.path
        XCTAssertTrue(resolved!.path.hasPrefix(baseCanonical))

        // Traversal and absolute paths are rejected.
        XCTAssertNil(handler.imageURL(forToken: "../secret.txt"))
        XCTAssertNil(handler.imageURL(forToken: "/etc/passwd"))

        // With no document directory, nothing resolves.
        handler.documentDirectory = nil
        XCTAssertNil(handler.imageURL(forToken: "local.png"))

        // A symlink inside the folder pointing outside is rejected (canonicalized).
        handler.documentDirectory = docDir
        let link = docDir.appendingPathComponent("link.txt")
        try fm.createSymbolicLink(at: link, withDestinationURL: secret)
        XCTAssertNil(handler.imageURL(forToken: "link.txt"))
    }
}
