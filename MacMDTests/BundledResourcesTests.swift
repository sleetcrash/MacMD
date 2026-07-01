import XCTest
import JavaScriptCore

/// Proves the Preview bundle resources (M1.7 vendoring + M1.8 registration) are
/// present in the app bundle and well-formed. Pure test code: it reads resources
/// via `Bundle.main` (the hosted test target's main bundle is MacMD.app) and
/// exercises the JS in a `JSContext`; no app symbols are referenced.
final class BundledResourcesTests: XCTestCase {

    private func resource(_ name: String, _ ext: String) -> String? {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    func testPreviewShellLoadsWithPlaceholders() {
        let html = resource("preview", "html")
        XCTAssertNotNil(html, "preview.html must be bundled")
        XCTAssertFalse(html?.isEmpty ?? true)
        XCTAssertTrue(html?.contains("__MACMD_NONCE__") ?? false, "shell must carry the nonce placeholder")
        XCTAssertTrue(html?.contains("__MACMD_CSS__") ?? false, "shell must carry the theme-CSS placeholder")
    }

    func testMarkdownItLoadsAndExposesFactory() {
        guard let js = resource("markdown-it.min", "js") else {
            return XCTFail("markdown-it.min.js missing from bundle")
        }
        let context = JSContext()!
        // The UMD wrapper falls back to attaching `markdownit` to a global; give
        // it the browser-ish globals it probes for.
        context.evaluateScript("var globalThis = this; var self = this;")
        context.evaluateScript(js)
        XCTAssertEqual(context.evaluateScript("typeof markdownit")?.toString(), "function")
    }

    func testMermaidBundleIsSelfContainedIIFE() {
        guard let js = resource("mermaid.min", "js") else {
            return XCTFail("mermaid.min.js missing from bundle")
        }
        XCTAssertTrue(js.contains("mermaid"))
        XCTAssertTrue(js.contains("window.mermaid"), "the IIFE assigns the global directly (not window.mermaid.default)")
        // No leaked top-level ESM module syntax (proves the esbuild IIFE bundling).
        XCTAssertFalse(js.contains("\nimport "), "no leaked top-level import")
        XCTAssertFalse(js.contains("\nexport "), "no leaked top-level export")
        // No bare external CommonJS require. esbuild's local `__require(` helper and
        // a dependency's guarded `.require("util")` browser/node feature-detect both
        // legitimately contain the substring "require(" while staying fully
        // self-contained, so strip those two forms before asserting.
        let bareRequire = js
            .replacingOccurrences(of: "__require(", with: "")
            .replacingOccurrences(of: ".require(", with: "")
        XCTAssertFalse(bareRequire.contains("require("), "bundle must contain no external CommonJS require")
    }

    func testPreviewBaseCSSLoads() {
        let css = resource("preview-base", "css")
        XCTAssertNotNil(css, "preview-base.css must be bundled")
        XCTAssertFalse(css?.isEmpty ?? true)
    }
}
