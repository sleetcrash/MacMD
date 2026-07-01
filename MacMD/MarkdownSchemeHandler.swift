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

    // Real request routing (shell + CSP header + bundled assets + images) lands
    // in M1.13; until then the handler fails any task cleanly.
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        urlSchemeTask.didFailWithError(URLError(.unsupportedURL))
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}
