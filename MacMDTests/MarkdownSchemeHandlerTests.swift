import XCTest
import WebKit
@testable import MacMD

@MainActor
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

    // MARK: - Serving (start routing)

    func testIndexResponseCarriesCSPHeaderAnd200() {
        let handler = MarkdownSchemeHandler()
        let url = URL(string: "macmd-resource://app/index.html")!
        let task = FakeSchemeTask(url: url)
        handler.webView(WKWebView(), start: task)

        let http = task.response as? HTTPURLResponse
        XCTAssertEqual(http?.statusCode, 200)
        XCTAssertTrue((http?.value(forHTTPHeaderField: "Content-Type") ?? "").hasPrefix("text/html"))
        XCTAssertTrue(task.finished)

        // The header CSP must match the nonce actually stamped into the served body.
        let body = String(data: task.data, encoding: .utf8) ?? ""
        let nonce = firstNonce(in: body)
        XCTAssertNotNil(nonce)
        XCTAssertEqual(http?.value(forHTTPHeaderField: "Content-Security-Policy"),
                       MarkdownRenderEngine.cspHeaderValue(nonce: nonce ?? ""))
    }

    func testBundledScriptIsServedWithJSMime() {
        let handler = MarkdownSchemeHandler()
        let url = URL(string: "macmd-resource://app/markdown-it.min.js")!
        let task = FakeSchemeTask(url: url)
        handler.webView(WKWebView(), start: task)

        let http = task.response as? HTTPURLResponse
        XCTAssertEqual(http?.statusCode, 200)
        XCTAssertTrue((http?.value(forHTTPHeaderField: "Content-Type") ?? "").contains("javascript"))
        XCTAssertFalse(task.data.isEmpty)
    }

    func testUnknownPathReturns404() {
        let handler = MarkdownSchemeHandler()
        let url = URL(string: "macmd-resource://app/does-not-exist")!
        let task = FakeSchemeTask(url: url)
        handler.webView(WKWebView(), start: task)
        XCTAssertEqual((task.response as? HTTPURLResponse)?.statusCode, 404)
    }

    func testTraversalImageTokenReturns404() throws {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        let handler = MarkdownSchemeHandler()
        handler.documentDirectory = tempDir
        let url = URL(string: "macmd-resource://img/..%2F..%2Fsecret")!
        let task = FakeSchemeTask(url: url)
        handler.webView(WKWebView(), start: task)
        XCTAssertEqual((task.response as? HTTPURLResponse)?.statusCode, 404)
    }

    func testPercentEncodedImageTokenResolvesLiteralPercentFilename() throws {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }
        try Data("png".utf8).write(to: tempDir.appendingPathComponent("50%.png"))

        let handler = MarkdownSchemeHandler()
        handler.documentDirectory = tempDir
        // A contained file named `50%.png` is referenced as `50%25.png`; the token
        // must be decoded exactly once and serve, not double-decode into a 404.
        let url = URL(string: "macmd-resource://img/50%25.png")!
        let task = FakeSchemeTask(url: url)
        handler.webView(WKWebView(), start: task)
        XCTAssertEqual((task.response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertFalse(task.data.isEmpty)
    }

    private func firstNonce(in html: String) -> String? {
        guard let open = html.range(of: "nonce=\"") else { return nil }
        let rest = html[open.upperBound...]
        guard let close = rest.firstIndex(of: "\"") else { return nil }
        return String(rest[..<close])
    }
}

/// Minimal WKURLSchemeTask double: captures the response, body, and completion so
/// the handler's synchronous routing can be asserted without a live web view.
private final class FakeSchemeTask: NSObject, WKURLSchemeTask {
    let request: URLRequest
    private(set) var response: URLResponse?
    private(set) var data = Data()
    private(set) var finished = false
    private(set) var error: Error?

    init(url: URL) { request = URLRequest(url: url) }

    func didReceive(_ response: URLResponse) { self.response = response }
    func didReceive(_ data: Data) { self.data.append(data) }
    func didFinish() { finished = true }
    func didFailWithError(_ error: Error) { self.error = error }
}
