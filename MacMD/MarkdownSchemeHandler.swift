import WebKit

/// Serves the sandboxed preview's resources over the custom `macmd-resource:`
/// scheme so the web origin has no filesystem reach: Swift is the sole
/// gatekeeper. It vends the shell + CSP header and the bundled JS/CSS (M1.13),
/// and path-validated local images. Image tokens are canonicalized and
/// containment-checked against the document's directory so a document can never
/// reference a file outside its own folder (traversal, absolute paths, and
/// escaping symlinks are all rejected).
final class MarkdownSchemeHandler: NSObject, WKURLSchemeHandler {

    static let scheme = "macmd-resource"

    /// The directory of the document being previewed. Local images resolve only
    /// inside it; `nil` means no local image resolves.
    var documentDirectory: URL?

    /// Resolve a local image token to a filesystem URL, or `nil` if it escapes
    /// the document directory. Canonicalizes both the directory and the candidate
    /// (following symlinks) and requires the candidate to sit inside the directory.
    func imageURL(forToken token: String) -> URL? {
        guard let documentDirectory else { return nil }
        guard let decoded = token.removingPercentEncoding, !decoded.isEmpty else { return nil }
        // Reject absolute paths outright; only document-relative tokens are served.
        guard !decoded.hasPrefix("/") else { return nil }

        let base = documentDirectory.resolvingSymlinksInPath().standardizedFileURL
        let candidate = documentDirectory.appendingPathComponent(decoded)
            .resolvingSymlinksInPath().standardizedFileURL

        let basePath = base.path
        let prefix = basePath.hasSuffix("/") ? basePath : basePath + "/"
        guard candidate.path.hasPrefix(prefix) else { return nil }
        return candidate
    }

    // MARK: - WKURLSchemeHandler

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url, let host = url.host else {
            respond(urlSchemeTask, url: urlSchemeTask.request.url, status: 404, headers: [:], data: Data())
            return
        }
        switch host {
        case "app": serveAppResource(url: url, to: urlSchemeTask)
        case "img": serveImage(url: url, to: urlSchemeTask)
        default:    respond(urlSchemeTask, url: url, status: 404, headers: [:], data: Data())
        }
    }

    // Responses are fully synchronous (all bytes are in hand), so stop is a no-op.
    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    // MARK: - Routing

    /// `app/index.html` gets the shell plus a matching per-render CSP header;
    /// `app/*.js` and `app/*.css` are served from the bundle; anything else 404s.
    private func serveAppResource(url: URL, to task: WKURLSchemeTask) {
        if url.lastPathComponent == "index.html" {
            let nonce = MarkdownRenderEngine.makeNonce()
            let body = MarkdownRenderEngine.shellHTML(nonce: nonce, css: "")
            respond(task, url: url, status: 200, headers: [
                "Content-Type": "text/html; charset=utf-8",
                "Content-Security-Policy": MarkdownRenderEngine.cspHeaderValue(nonce: nonce),
            ], data: Data(body.utf8))
            return
        }
        let ext = url.pathExtension
        let base = url.deletingPathExtension().lastPathComponent
        guard ext == "js" || ext == "css",
              let fileURL = Bundle.main.url(forResource: base, withExtension: ext),
              let data = try? Data(contentsOf: fileURL) else {
            respond(task, url: url, status: 404, headers: [:], data: Data())
            return
        }
        let mime = ext == "js" ? "text/javascript" : "text/css"
        respond(task, url: url, status: 200, headers: ["Content-Type": mime], data: data)
    }

    /// `img/<token>` serves a path-validated local image, or 404s if the token
    /// escapes the document directory or the file cannot be read.
    private func serveImage(url: URL, to task: WKURLSchemeTask) {
        let token = String(url.path.dropFirst())
        guard let fileURL = imageURL(forToken: token),
              let data = try? Data(contentsOf: fileURL) else {
            respond(task, url: url, status: 404, headers: [:], data: Data())
            return
        }
        respond(task, url: url, status: 200, headers: ["Content-Type": Self.imageMIME(for: fileURL)], data: data)
    }

    private func respond(_ task: WKURLSchemeTask, url: URL?, status: Int, headers: [String: String], data: Data) {
        let responseURL = url ?? URL(string: "\(Self.scheme)://invalid")!
        let response = HTTPURLResponse(url: responseURL, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    private static func imageMIME(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "svg": return "image/svg+xml"
        case "webp": return "image/webp"
        case "bmp": return "image/bmp"
        case "tiff", "tif": return "image/tiff"
        default: return "application/octet-stream"
        }
    }
}
