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
}
