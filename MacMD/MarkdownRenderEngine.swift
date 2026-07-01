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
}
