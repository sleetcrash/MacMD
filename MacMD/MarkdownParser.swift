import Foundation

/// Pure markdown structural parsing, extracted from `MarkdownHighlighter`'s
/// file-private `MarkdownRules` so the render pre-pass and the outline can reuse
/// it off the main actor. A non-isolated enum: on this toolchain
/// `NSRegularExpression` is `Sendable`, so the cached pattern is a plain
/// concurrency-safe `static let`. Behavior is byte-for-byte identical to the
/// highlighter's prior inline implementation (its fence regression tests must
/// stay green).
enum MarkdownParser {

    // MARK: - Fenced code

    struct FenceLine: Equatable {
        let range: NSRange
        let marker: Character
    }

    static let fencePattern: NSRegularExpression =
        makeRegex("^[ \\t]*(`{3,}|~{3,})[^\\n]*$", options: [.anchorsMatchLines])

    static func fenceLines(in nsString: NSString, fullRange: NSRange) -> [FenceLine] {
        var lines: [FenceLine] = []
        fencePattern.enumerateMatches(in: nsString as String, options: [], range: fullRange) { match, _, _ in
            guard let m = match else { return }
            let markerGroup = m.range(at: 1)
            guard markerGroup.location != NSNotFound else { return }
            let markerString = nsString.substring(with: NSRange(location: markerGroup.location, length: 1))
            guard let marker = markerString.first else { return }
            lines.append(FenceLine(range: m.range, marker: marker))
        }
        return lines
    }

    static func spansFromFences(_ lines: [FenceLine], fullRange: NSRange) -> [NSRange] {
        var spans: [NSRange] = []
        var i = 0
        while i < lines.count {
            let open = lines[i]
            var closeIndex: Int? = nil
            var j = i + 1
            while j < lines.count {
                if lines[j].marker == open.marker {
                    closeIndex = j
                    break
                }
                j += 1
            }
            if let close = closeIndex {
                let start = open.range.location
                let end = lines[close].range.location + lines[close].range.length
                spans.append(NSRange(location: start, length: end - start))
                i = close + 1
            } else {
                let start = open.range.location
                let end = fullRange.location + fullRange.length
                spans.append(NSRange(location: start, length: end - start))
                i += 1
            }
        }
        return spans
    }

    /// Convenience over the whole document: pairs `fenceLines` then
    /// `spansFromFences`. The render pre-pass and the outline call this; the
    /// highlighter keeps the two-step form so it can compare `fenceLines` arrays
    /// for change detection without recomputing.
    static func fenceSpans(in text: String) -> [NSRange] {
        let nsString = text as NSString
        let full = NSRange(location: 0, length: nsString.length)
        return spansFromFences(fenceLines(in: nsString, fullRange: full), fullRange: full)
    }

    // MARK: - Range helpers

    static func intersectsAny(_ range: NSRange, ranges: [NSRange]) -> Bool {
        for r in ranges where NSIntersectionRange(r, range).length > 0 { return true }
        return false
    }

    // MARK: - Regex helper

    static func makeRegex(_ pattern: String, options: NSRegularExpression.Options = []) -> NSRegularExpression {
        do {
            return try NSRegularExpression(pattern: pattern, options: options)
        } catch {
            fatalError("MarkdownParser: pattern \(pattern) failed to compile: \(error)")
        }
    }
}
