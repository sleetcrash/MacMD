import AppKit
import UniformTypeIdentifiers
import WebKit

/// Exports the rendered document as a single-page PDF through the same
/// sandboxed offline render pipeline as the preview and the HTML export. The
/// output is FULL-BLEED: the theme background reaches every edge. (Print's
/// Save-as-PDF paginates the raw editor text inside printer margins, which
/// left a white border around dark themes; this path exists to avoid that.)
enum PDFExporter {

    /// The rendered page width in points: the preview column (760) plus the
    /// shell body padding (28 per side).
    static let pageWidth: CGFloat = 816

    /// Render `markdown` under `theme` and return single-page PDF data, or nil
    /// if the shell failed to load or produce a PDF.
    @MainActor
    static func makePDF(markdown: String, theme: ThemeController,
                        documentDirectory: URL? = nil) async -> Data? {
        let config = WKWebViewConfiguration()
        let handler = MarkdownSchemeHandler()
        handler.documentDirectory = documentDirectory
        config.setURLSchemeHandler(handler, forURLScheme: MarkdownSchemeHandler.scheme)
        config.websiteDataStore = .nonPersistent()

        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: pageWidth, height: 1000),
                                configuration: config)
        let loader = ExportLoader()
        webView.navigationDelegate = loader
        webView.load(URLRequest(url: URL(string: "\(MarkdownSchemeHandler.scheme)://app/index.html")!))
        await loader.waitForLoad()

        let appearanceClass = EditorBackground.effectiveAppearance(
            mode: theme.backgroundMode, hex: theme.customBackgroundHex, appearance: theme.appearance
        ).resolvesDark ? "darkAqua" : "aqua"
        // Same-page evaluateJavaScript calls execute in order, so the setters
        // and render can fire and forget; the poll below gates completion.
        webView.evaluateJavaScript("window.setThemeCSS(\(MarkdownRenderEngine.jsStringLiteral(PreviewCSS.css(theme: theme))))", completionHandler: nil)
        webView.evaluateJavaScript("window.setAppearance(\(MarkdownRenderEngine.jsStringLiteral(appearanceClass)))", completionHandler: nil)

        // Render and wait for the completion flag so async mermaid SVG is in
        // the DOM before measuring (the PreviewHarness pattern).
        let before = await evalNumber("window.__renderComplete || 0", in: webView) ?? 0
        webView.evaluateJavaScript(MarkdownRenderEngine.renderInvocation(markdown: markdown), completionHandler: nil)
        for _ in 0..<120 {
            let now = await evalNumber("window.__renderComplete || 0", in: webView) ?? 0
            if now > before { break }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        // Size the view to the whole document so one PDF page captures it all.
        let measured = await evalNumber("document.documentElement.scrollHeight", in: webView) ?? 0
        webView.frame.size.height = max(measured, 100)
        try? await Task.sleep(nanoseconds: 100_000_000)   // let the resize lay out

        // The async pdf(configuration:) keeps the web view alive across the
        // await (a completion-handler createPDF would not pin it, and an
        // early-released view never calls back). Unlike evaluateJavaScript's
        // async overload there is no nil-result trap here: it returns Data or
        // throws.
        return try? await webView.pdf(configuration: WKPDFConfiguration())
    }

    /// Render the document and present a save panel to write the `.pdf`.
    /// Fire-and-forget from a menu command; the render is async.
    @MainActor
    static func export(markdown: String, theme: ThemeController, in window: NSWindow?) {
        let name = HTMLExporter.suggestedFilename(representedURL: window?.representedURL,
                                                  windowTitle: window?.title, ext: "pdf")
        let documentDirectory = window?.representedURL?.deletingLastPathComponent()
        Task { @MainActor in
            let data = await makePDF(markdown: markdown, theme: theme,
                                     documentDirectory: documentDirectory)
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.pdf]
            panel.nameFieldStringValue = name
            let response: NSApplication.ModalResponse
            if let window {
                response = await panel.beginSheetModal(for: window)
            } else {
                response = panel.runModal()
            }
            guard response == .OK, let url = panel.url else { return }
            do {
                guard let data else {
                    throw CocoaError(.fileWriteUnknown)
                }
                try data.write(to: url)
            } catch {
                let alert = NSAlert(error: error)
                alert.messageText = "Could not export to PDF"
                if let window {
                    alert.beginSheetModal(for: window, completionHandler: nil)
                } else {
                    alert.runModal()
                }
            }
        }
    }

    /// Completion-handler JS bridge for numeric reads (the async
    /// evaluateJavaScript overload traps on a nil/undefined result, and a raw
    /// `Any?` cannot cross the continuation under strict concurrency).
    @MainActor
    private static func evalNumber(_ js: String, in webView: WKWebView) async -> Double? {
        await withCheckedContinuation { continuation in
            webView.evaluateJavaScript(js) { result, _ in
                continuation.resume(returning: (result as? NSNumber)?.doubleValue)
            }
        }
    }
}
