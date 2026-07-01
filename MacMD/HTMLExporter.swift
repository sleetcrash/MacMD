import AppKit
import UniformTypeIdentifiers
import WebKit

/// Exports the current document to a single self-contained `.html` file: the
/// markdown-it body plus inline CSS (the same base + theme CSS the preview uses),
/// with no external references, so the file is portable and fully offline. Runs a
/// headless off-screen WKWebView through the M1 render pipeline. M4 adds inline
/// mermaid SVG to this same path.
enum HTMLExporter {

    /// Produce the self-contained HTML string for `markdown` under `theme`.
    /// `documentDirectory` (the edited file's folder) lets contained local images
    /// be inlined as data: URIs; external image references are always dropped.
    @MainActor
    static func makeSelfContainedHTML(markdown: String, theme: ThemeController,
                                      documentDirectory: URL? = nil) async -> String {
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
        body = inlineLocalImages(in: body, documentDirectory: documentDirectory)

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

    /// Render the document and present a save panel to write a self-contained
    /// `.html` file. Fire-and-forget from a menu command; the render is async.
    @MainActor
    static func export(markdown: String, theme: ThemeController, in window: NSWindow?) {
        let name = suggestedFilename(representedURL: window?.representedURL, windowTitle: window?.title)
        let documentDirectory = window?.representedURL?.deletingLastPathComponent()
        Task { @MainActor in
            let html = await makeSelfContainedHTML(markdown: markdown, theme: theme,
                                                   documentDirectory: documentDirectory)
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.html]
            panel.nameFieldStringValue = name
            let response: NSApplication.ModalResponse
            if let window {
                response = await panel.beginSheetModal(for: window)
            } else {
                response = panel.runModal()
            }
            guard response == .OK, let url = panel.url else { return }
            do {
                try html.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                let alert = NSAlert(error: error)
                alert.messageText = "Could not export to HTML"
                if let window {
                    alert.beginSheetModal(for: window, completionHandler: nil)
                } else {
                    alert.runModal()
                }
            }
        }
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

    /// Rewrite each document-relative `<img src="...">` to a self-contained data:
    /// URI (read from `documentDirectory` with the same canonicalize + containment
    /// check the preview uses), or drop the src if it cannot be safely resolved.
    /// External srcs were already removed in the render JS, and data: URIs are
    /// left as-is, so the output holds no network references.
    private static func inlineLocalImages(in html: String, documentDirectory: URL?) -> String {
        guard let regex = try? NSRegularExpression(pattern: "<img\\b[^>]*?\\ssrc=\"([^\"]*)\"") else { return html }
        let handler = MarkdownSchemeHandler()
        handler.documentDirectory = documentDirectory

        var result = html
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: (html as NSString).length))
        // Replace from the end so earlier match ranges stay valid.
        for match in matches.reversed() {
            let srcRange = match.range(at: 1)
            guard srcRange.location != NSNotFound else { continue }
            let src = (html as NSString).substring(with: srcRange)
            if src.hasPrefix("data:") { continue }

            let replacement: String
            if let fileURL = handler.imageURL(forToken: src), let data = try? Data(contentsOf: fileURL) {
                replacement = "data:\(MarkdownSchemeHandler.imageMIME(for: fileURL));base64,\(data.base64EncodedString())"
            } else {
                replacement = ""   // unresolvable or escaping: drop the reference
            }
            result = (result as NSString).replacingCharacters(in: srcRange, with: replacement)
        }
        return result
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
