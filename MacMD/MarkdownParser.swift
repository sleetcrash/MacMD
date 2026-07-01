import Foundation

/// A parsed markdown heading for the outline and render pre-pass. `lineRange` is
/// the heading text line (for setext, the title line, not the underline),
/// excluding the trailing newline.
struct MarkdownHeading: Equatable {
    let level: Int
    let title: String
    let lineRange: NSRange
}

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

    /// The language/info string of every OPENING fence, in document order. The
    /// highlighter discards these, but the render pre-pass needs them to detect
    /// mermaid fences. `info` is the opening line minus its leading indent and
    /// fence-character run, trimmed; `lineRange` is the opening fence line only.
    static func openingFenceInfo(in text: String) -> [(lineRange: NSRange, info: String)] {
        let nsString = text as NSString
        let full = NSRange(location: 0, length: nsString.length)
        let lines = fenceLines(in: nsString, fullRange: full)
        var result: [(lineRange: NSRange, info: String)] = []
        var i = 0
        while i < lines.count {
            let open = lines[i]
            let lineText = nsString.substring(with: open.range)
            let afterIndent = lineText.drop(while: { $0 == " " || $0 == "\t" })
            let info = String(afterIndent.drop(while: { $0 == open.marker }))
                .trimmingCharacters(in: .whitespaces)
            result.append((lineRange: open.range, info: info))
            // Skip past the matching closing fence, mirroring spansFromFences.
            var closeIndex: Int? = nil
            var j = i + 1
            while j < lines.count {
                if lines[j].marker == open.marker { closeIndex = j; break }
                j += 1
            }
            i = closeIndex.map { $0 + 1 } ?? (i + 1)
        }
        return result
    }

    // MARK: - Headings

    struct HeadingLine: Equatable {
        let range: NSRange
        let level: Int
    }

    static let headingPattern: NSRegularExpression =
        makeRegex("^(#{1,6})[ \\t]+.+$", options: [.anchorsMatchLines])

    static func headingLines(in nsString: NSString, fullRange: NSRange) -> [HeadingLine] {
        var lines: [HeadingLine] = []
        headingPattern.enumerateMatches(in: nsString as String, options: [], range: fullRange) { match, _, _ in
            guard let m = match else { return }
            let hashes = m.range(at: 1)
            lines.append(HeadingLine(range: m.range, level: min(6, max(1, hashes.length))))
        }
        return lines
    }

    /// Every heading in document order: ATX (`#`..`######`) plus setext (a text
    /// line underlined by a run of `=` for H1 or `-` for H2), with any heading
    /// inside a fenced code block excluded. `MarkdownHeading.lineRange` is the
    /// heading text line (the title line for setext), excluding the trailing
    /// newline. Purely additive: the editor highlighter stays ATX-only and does
    /// not call this.
    static func headings(in text: String) -> [MarkdownHeading] {
        let nsString = text as NSString
        let full = NSRange(location: 0, length: nsString.length)
        guard full.length > 0 else { return [] }
        let fences = fenceSpans(in: text)
        var result: [MarkdownHeading] = []

        // ATX: reuse the existing primitive; drop any heading inside a fence.
        for line in headingLines(in: nsString, fullRange: full)
        where !intersectsAny(line.range, ranges: fences) {
            let raw = nsString.substring(with: line.range)
            let title = String(raw.drop(while: { $0 == "#" })).trimmingCharacters(in: .whitespaces)
            result.append(MarkdownHeading(level: line.level, title: title, lineRange: line.range))
        }

        // Setext: a non-blank text line immediately followed by an underline line
        // of only `=` (H1) or only `-` (H2). A blank line before the underline (a
        // thematic break) or a fenced region breaks the pattern.
        let lineRanges = contentLineRanges(in: nsString)
        for i in lineRanges.indices where i + 1 < lineRanges.count {
            let titleRange = lineRanges[i]
            let underlineRange = lineRanges[i + 1]
            guard titleRange.length > 0, underlineRange.length > 0 else { continue }
            guard !intersectsAny(titleRange, ranges: fences),
                  !intersectsAny(underlineRange, ranges: fences) else { continue }
            let title = nsString.substring(with: titleRange).trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty, !title.hasPrefix("#") else { continue }
            let underline = nsString.substring(with: underlineRange).trimmingCharacters(in: .whitespaces)
            let level: Int
            if isUnderlineRun(underline, "=") { level = 1 }
            else if isUnderlineRun(underline, "-") { level = 2 }
            else { continue }
            result.append(MarkdownHeading(level: level, title: title, lineRange: titleRange))
        }

        return result.sorted { $0.lineRange.location < $1.lineRange.location }
    }

    /// Content ranges (each excluding its trailing newline) of every line, in order.
    private static func contentLineRanges(in nsString: NSString) -> [NSRange] {
        var ranges: [NSRange] = []
        var idx = 0
        while idx < nsString.length {
            var ls = 0, le = 0, ce = 0
            nsString.getLineStart(&ls, end: &le, contentsEnd: &ce, for: NSRange(location: idx, length: 0))
            ranges.append(NSRange(location: ls, length: ce - ls))
            guard le > idx else { break }
            idx = le
        }
        return ranges
    }

    private static func isUnderlineRun(_ trimmed: String, _ ch: Character) -> Bool {
        !trimmed.isEmpty && trimmed.allSatisfy { $0 == ch }
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
