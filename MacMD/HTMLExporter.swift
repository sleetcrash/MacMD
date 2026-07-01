import WebKit

/// Exports the current document to a single self-contained `.html` file: the
/// markdown-it body plus inline CSS (the same base + theme CSS the preview uses),
/// with no external references, so the file is portable and fully offline. Runs a
/// headless off-screen WKWebView through the M1 render pipeline. M4 adds inline
/// mermaid SVG to this same path.
enum HTMLExporter {

    /// Produce the self-contained HTML string for `markdown` under `theme`.
    @MainActor
    static func makeSelfContainedHTML(markdown: String, theme: ThemeController) async -> String {
        let baseCSS = bundledCSS("preview-base")
        let themeCSS = PreviewCSS.css(theme: theme)
        let appearanceClass = EditorBackground.effectiveAppearance(
            mode: theme.backgroundMode, hex: theme.customBackgroundHex, appearance: theme.appearance
        ).resolvesDark ? "darkAqua" : "aqua"

        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(MarkdownSchemeHandler(), forURLScheme: MarkdownSchemeHandler.scheme)
        config.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: config)
        let loader = ExportLoader()
        webView.navigationDelegate = loader
        webView.load(URLRequest(url: URL(string: "\(MarkdownSchemeHandler.scheme)://app/index.html")!))
        await loader.waitForLoad()

        var body = ""
        if let result = try? await webView.callAsyncJavaScript(
            "return window.renderForExport(markdown)",
            arguments: ["markdown": markdown], contentWorld: .page) {
            body = (result as? String) ?? ""
        }
        // The local `webView` stays alive for the whole scope, including the awaits.

        return """
        <!DOCTYPE html>
        <html class="\(appearanceClass)">
        <head>
        <meta charset="utf-8">
        <style>
        \(baseCSS)
        \(themeCSS)
        </style>
        </head>
        <body class="markdown-body">
        \(body)
        </body>
        </html>
        """
    }

    /// The default export filename: the document's name with a `.html` extension,
    /// falling back to the window title (extension stripped) then `Untitled`.
    static func suggestedFilename(representedURL: URL?, windowTitle: String?) -> String {
        let raw: String
        if let url = representedURL {
            raw = url.deletingPathExtension().lastPathComponent
        } else if let title = windowTitle, !title.isEmpty {
            raw = (title as NSString).deletingPathExtension
        } else {
            raw = ""
        }
        return (raw.isEmpty ? "Untitled" : raw) + ".html"
    }

    private static func bundledCSS(_ name: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: "css"),
              let css = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return css
    }
}

/// Bridges the off-screen web view's one-time load into async/await.
@MainActor
private final class ExportLoader: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Never>?

    func waitForLoad() async {
        await withCheckedContinuation { self.continuation = $0 }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finish() }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finish() }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finish() }

    private func finish() {
        continuation?.resume()
        continuation = nil
    }
}
