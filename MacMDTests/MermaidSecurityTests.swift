import XCTest
import WebKit
@testable import MacMD

@MainActor
final class MermaidSecurityTests: XCTestCase {

    /// RELEASE GATE: every shipped diagram type must render with zero CSP
    /// violation. If a type fires a script-src (eval / new Function) violation at
    /// the pinned mermaid version, drop it from this list AND from the render JS's
    /// accepted set and record the drop; never relax the CSP to keep it.
    func testEachShippedDiagramTypeRendersWithoutCSPViolation() async {
        let h = PreviewHarness()
        await h.load()
        await h.eval("window.__cspViolations = []; document.addEventListener('securitypolicyviolation', function(e){ window.__cspViolations.push(e.violatedDirective); });")

        let types: [(name: String, source: String)] = [
            ("flowchart", "flowchart TD\n  A-->B"),
            ("sequenceDiagram", "sequenceDiagram\n  Alice->>Bob: Hi"),
            ("classDiagram", "classDiagram\n  Animal <|-- Dog"),
            ("stateDiagram-v2", "stateDiagram-v2\n  [*] --> S1"),
            ("erDiagram", "erDiagram\n  CUSTOMER ||--o{ ORDER : places"),
            ("gantt", "gantt\n  title G\n  section S\n  Task :a1, 2024-01-01, 30d"),
            ("pie", "pie title Pets\n  \"Dogs\" : 386\n  \"Cats\" : 85"),
            ("mindmap", "mindmap\n  root((mind))\n    A\n    B"),
            ("gitGraph", "gitGraph\n  commit\n  commit"),
            ("journey", "journey\n  title My day\n  section Go\n  Wake: 5: Me"),
            ("timeline", "timeline\n  title History\n  2002 : LinkedIn"),
            ("quadrantChart", "quadrantChart\n  title R\n  x-axis Low --> High\n  y-axis Low --> High\n  Point: [0.3, 0.6]"),
        ]

        var failures: [String] = []
        for t in types {
            let before = (await h.eval("window.__cspViolations.length") as? NSNumber)?.intValue ?? 0
            await h.renderAndWait("```mermaid\n\(t.source)\n```\n")
            let svg = (await h.eval("document.querySelectorAll('svg').length") as? NSNumber)?.intValue ?? 0
            let after = (await h.eval("window.__cspViolations.length") as? NSNumber)?.intValue ?? 0
            if svg < 1 { failures.append("\(t.name): no svg rendered") }
            if after > before { failures.append("\(t.name): CSP violation") }
        }
        XCTAssertTrue(failures.isEmpty, "diagram types that failed the eval-check: \(failures)")
    }

    /// A malicious mermaid payload cannot execute under securityLevel:'strict'.
    func testMaliciousMermaidLabelDoesNotExecute() async {
        let h = PreviewHarness()
        await h.load()
        await h.eval("window.__cspViolations = []; window.__pwned = false; document.addEventListener('securitypolicyviolation', function(e){ window.__cspViolations.push(e.violatedDirective); });")

        let source = "flowchart TD\n  A[\"<img src=x onerror='window.__pwned=true'>\"]\n  click A \"javascript:window.__pwned=true\""
        await h.renderAndWait("```mermaid\n\(source)\n```\n")

        let pwned = (await h.eval("window.__pwned === true") as? NSNumber)?.boolValue ?? false
        XCTAssertFalse(pwned, "the injected handler / click binding did not execute")
        let svg = (await h.eval("document.querySelectorAll('svg').length") as? NSNumber)?.intValue ?? 0
        XCTAssertGreaterThanOrEqual(svg, 1, "the legitimate node still renders (sanitized, not blank)")
        let violations = (await h.eval("window.__cspViolations.length") as? NSNumber)?.intValue ?? -1
        XCTAssertEqual(violations, 0)
    }
}
