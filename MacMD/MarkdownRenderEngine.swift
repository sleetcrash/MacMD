import Foundation
import Security

/// Pure builders for the sandboxed WKWebView render pipeline: the per-render
/// nonce, the locked Content-Security-Policy, the shell HTML, and the JS render
/// invocation. No WebKit dependency, so it is unit-testable and callable off the
/// main actor. One engine serves the preview pane and the HTML export.
enum MarkdownRenderEngine {

    /// A fresh 128-bit nonce, base64-encoded, for the CSP header and the shell's
    /// script/style tags. Untrusted inline scripts, `onerror` handlers, and
    /// `javascript:` URLs never carry it, so the CSP denies them execution.
    static func makeNonce() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed with status \(status)")
        return Data(bytes).base64EncodedString()
    }

    /// The locked Content-Security-Policy, delivered as a real HTTP header by the
    /// scheme handler. Only the single `script-src 'nonce-...'` slot is
    /// parameterized. `script-src` carries the nonce and NO `'unsafe-inline'`, so
    /// untrusted inline scripts, `onerror` handlers, and `javascript:` URLs are
    /// denied execution. `style-src` uses `'unsafe-inline'` with NO nonce: per
    /// CSP3 a nonce on `style-src` makes `'unsafe-inline'` ignored, which would
    /// block mermaid's runtime-injected styles (inline styles are not code
    /// execution and markdown-it `html:false` escapes untrusted `<style>`).
    /// `'unsafe-eval'` is never present (a red line). Network is fully denied
    /// (`connect-src 'none'`, remote `img-src`/`frame-src` blocked).
    static func cspHeaderValue(nonce: String) -> String {
        "default-src 'none'; "
            + "script-src 'nonce-\(nonce)'; "
            + "style-src 'unsafe-inline' macmd-resource:; "
            + "img-src macmd-resource: data:; "
            + "font-src macmd-resource:; "
            + "connect-src 'none'; "
            + "object-src 'none'; "
            + "base-uri 'none'; "
            + "form-action 'none'; "
            + "frame-ancestors 'none'; "
            + "frame-src 'none'; "
            + "sandbox allow-scripts"
    }

    /// The shell HTML loaded ONCE per web view, with the per-render `nonce` and
    /// the theme `css` stamped into the bundled `preview.html` template's
    /// `__MACMD_NONCE__` / `__MACMD_CSS__` placeholders. In M1 the scheme handler
    /// passes `css: ""`; M2 passes `PreviewCSS.css(theme:)`. Returns "" only if
    /// the bundled template is missing (a packaging error the BundledResources
    /// tests gate against), so the preview degrades to blank rather than crashing.
    static func shellHTML(nonce: String, css: String) -> String {
        guard let url = Bundle.main.url(forResource: "preview", withExtension: "html"),
              let template = try? String(contentsOf: url, encoding: .utf8) else {
            return ""
        }
        return template
            .replacingOccurrences(of: "__MACMD_NONCE__", with: nonce)
            .replacingOccurrences(of: "__MACMD_CSS__", with: css)
    }

    /// The JS call delivered via `evaluateJavaScript` to push a document into the
    /// live preview: `window.render(<json>)`, where `<json>` is the markdown
    /// JSON-encoded as a single string fragment. Because it is delivered through
    /// `evaluateJavaScript` (never embedded in an inline `<script>`), the payload
    /// is treated purely as a string argument, so a `</script>` in the source is
    /// inert here; markdown-it `html:false` then escapes any raw HTML inside it.
    static func renderInvocation(markdown: String) -> String {
        "window.render(\(jsStringLiteral(markdown)))"
    }

    /// Whether the document contains at least one mermaid fence (an opening fence
    /// whose info string's first token is `mermaid`, case-insensitive). The
    /// render/export path uses this to decide whether to await mermaid completion.
    static func containsMermaid(in markdown: String) -> Bool {
        MarkdownParser.openingFenceInfo(in: markdown).contains {
            $0.info.split(separator: " ", maxSplits: 1).first?.lowercased() == "mermaid"
        }
    }

    /// A JSON-encoded JS string literal, so an arbitrary payload (markdown, CSS,
    /// an appearance name) is delivered to a `window.*` function as an inert
    /// string argument, never interpolated as code.
    static func jsStringLiteral(_ s: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: s, options: [.fragmentsAllowed]),
              let json = String(data: data, encoding: .utf8) else { return "\"\"" }
        return json
    }
}
