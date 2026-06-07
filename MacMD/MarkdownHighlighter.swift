import AppKit

@MainActor
final class MarkdownHighlighter: NSObject, @preconcurrency NSTextStorageDelegate {

    var isSuppressed = false
    var isDisabled = false
    private var lastFenceLines: [MarkdownRules.FenceLine] = []
    private var lastHeadingLines: [MarkdownRules.HeadingLine] = []
    private var lastFrontMatter: NSRange?

    func textStorage(_ textStorage: NSTextStorage,
                     didProcessEditing editedMask: NSTextStorageEditActions,
                     range editedRange: NSRange,
                     changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters), !isSuppressed, !isDisabled else { return }

        let nsString = textStorage.string as NSString
        let total = NSRange(location: 0, length: nsString.length)
        guard editedRange.location <= nsString.length else { return }

        let fenceLines = MarkdownRules.fenceLines(in: nsString, fullRange: total)
        let fencesChanged = fenceLines != lastFenceLines
        lastFenceLines = fenceLines

        let codeSpans = MarkdownRules.spansFromFences(fenceLines, fullRange: total)

        let frontMatter = MarkdownRules.frontMatterSpan(in: nsString, fullRange: total)
        let frontMatterChanged = frontMatter != lastFrontMatter
        lastFrontMatter = frontMatter

        let headings: [MarkdownRules.HeadingLine] = Theme.activeColoring == .off
            ? []
            : MarkdownRules.headingLines(in: nsString, fullRange: total)
        let headingsChanged = headings != lastHeadingLines
        lastHeadingLines = headings
        let sectionMap = MarkdownRules.sectionMap(from: headings, excluding: codeSpans)

        if fencesChanged || headingsChanged || frontMatterChanged {
            MarkdownRules.applyHighlighting(to: textStorage, in: total, fencedSpans: codeSpans, frontMatter: frontMatter, sectionMap: sectionMap)
            return
        }

        let paragraph = nsString.paragraphRange(for: editedRange)
        let targetRange: NSRange
        if let containing = codeSpans.first(where: { NSLocationInRange(paragraph.location, $0) || NSIntersectionRange($0, paragraph).length > 0 }) {
            targetRange = containing
        } else {
            targetRange = paragraph
        }

        MarkdownRules.applyHighlighting(to: textStorage, in: targetRange, fencedSpans: codeSpans, frontMatter: frontMatter, sectionMap: sectionMap)
    }

    func rehighlightAll(_ textStorage: NSTextStorage) {
        guard !isDisabled else { return }
        let nsString = textStorage.string as NSString
        let full = NSRange(location: 0, length: nsString.length)
        let fenceLines = MarkdownRules.fenceLines(in: nsString, fullRange: full)
        lastFenceLines = fenceLines
        let spans = MarkdownRules.spansFromFences(fenceLines, fullRange: full)
        let frontMatter = MarkdownRules.frontMatterSpan(in: nsString, fullRange: full)
        lastFrontMatter = frontMatter
        let headings: [MarkdownRules.HeadingLine] = Theme.activeColoring == .off
            ? []
            : MarkdownRules.headingLines(in: nsString, fullRange: full)
        lastHeadingLines = headings
        let sectionMap = MarkdownRules.sectionMap(from: headings, excluding: spans)
        MarkdownRules.applyHighlighting(to: textStorage, in: full, fencedSpans: spans, frontMatter: frontMatter, sectionMap: sectionMap)
    }

    /// Strip all styling back to base attributes, for Plain (formatting-off)
    /// mode: uniform body font + text color + base paragraph style, no code
    /// background, underline, or strikethrough. Leaves the text itself untouched.
    func clearHighlighting(_ textStorage: NSTextStorage) {
        let full = NSRange(location: 0, length: textStorage.length)
        guard full.length > 0 else { return }
        textStorage.beginEditing()
        textStorage.removeAttribute(.backgroundColor, range: full)
        textStorage.removeAttribute(.underlineStyle, range: full)
        textStorage.removeAttribute(.strikethroughStyle, range: full)
        textStorage.addAttribute(.font, value: Theme.editorFont, range: full)
        textStorage.addAttribute(.foregroundColor, value: Theme.textColor, range: full)
        textStorage.addAttribute(.paragraphStyle, value: Theme.bodyParagraphStyle, range: full)
        textStorage.endEditing()
    }

    func taskCheckboxRanges(in textStorage: NSTextStorage) -> [NSRange] {
        guard !isDisabled else { return [] }
        return MarkdownRules.taskCheckboxRanges(in: textStorage)
    }
}

@MainActor
private enum MarkdownRules {

    struct Rule {
        let regex: NSRegularExpression
        let apply: (NSTextStorage, NSTextCheckingResult, SectionMap) -> Void
    }

    static func r(_ pattern: String, options: NSRegularExpression.Options = []) -> NSRegularExpression {
        do {
            return try NSRegularExpression(pattern: pattern, options: options)
        } catch {
            fatalError("MarkdownHighlighter: pattern \(pattern) failed to compile: \(error)")
        }
    }

    static let fencePattern: NSRegularExpression = r("^[ \\t]*(`{3,}|~{3,})[^\\n]*$", options: [.anchorsMatchLines])

    struct FenceLine: Equatable {
        let range: NSRange
        let marker: Character
    }

    static let headingPattern: NSRegularExpression = r("^(#{1,6})[ \\t]+.+$", options: [.anchorsMatchLines])

    struct HeadingLine: Equatable {
        let range: NSRange
        let level: Int
    }

    static func headingLines(in nsString: NSString, fullRange: NSRange) -> [HeadingLine] {
        var lines: [HeadingLine] = []
        headingPattern.enumerateMatches(in: nsString as String, options: [], range: fullRange) { match, _, _ in
            guard let m = match else { return }
            let hashes = m.range(at: 1)
            lines.append(HeadingLine(range: m.range, level: min(6, max(1, hashes.length))))
        }
        return lines
    }

    static func sectionMap(from headings: [HeadingLine], excluding fencedSpans: [NSRange]) -> SectionMap {
        let usable = headings.filter { !intersectsAny($0.range, ranges: fencedSpans) }
        return SectionMap(headings: usable.map { (location: $0.range.location, level: $0.level) })
    }

    static let inlineRules: [Rule] = [
        Rule(regex: r("^([ \\t]*[-*+][ \\t]+)(\\[[ xX]\\])([ \\t]+)(.*)$", options: [.anchorsMatchLines])) { ts, m, map in
            let bracket = m.range(at: 2)
            let level = map.governingLevel(at: bracket.location)
            ts.addAttribute(.foregroundColor, value: Theme.headingColor(level: level), range: bracket)
            let nsString = ts.string as NSString
            let bracketString = nsString.substring(with: bracket)
            let isChecked = bracketString == "[x]" || bracketString == "[X]"
            if isChecked {
                let body = m.range(at: 4)
                if body.length > 0 {
                    ts.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: body)
                    ts.addAttribute(.foregroundColor, value: Theme.mutedColor, range: body)
                }
            }
        },
        Rule(regex: headingPattern) { ts, m, _ in
            let full = m.range
            let hashes = m.range(at: 1)
            let level = min(6, max(1, hashes.length))
            ts.addAttribute(.font, value: Theme.headingFont(level: level), range: full)
            ts.addAttribute(.foregroundColor, value: Theme.headingColor(level: level), range: full)
        },
        Rule(regex: r("\\*\\*(?!\\s)(?:[^*\\n]|\\*(?!\\*))+(?<!\\s)\\*\\*")) { ts, m, _ in
            addFontTrait(.bold, to: ts, in: m.range)
        },
        Rule(regex: r("(?<![A-Za-z0-9_])__(?!\\s)(?:[^_\\n]|_(?!_))+(?<!\\s)__(?![A-Za-z0-9_])")) { ts, m, _ in
            addFontTrait(.bold, to: ts, in: m.range)
        },
        Rule(regex: r("(?<![\\*A-Za-z0-9])\\*(?!\\s)[^*\\n]+(?<!\\s)\\*(?![\\*A-Za-z0-9])")) { ts, m, _ in
            addFontTrait(.italic, to: ts, in: m.range)
        },
        Rule(regex: r("(?<![A-Za-z0-9_])_(?!\\s)[^_\\n]+(?<!\\s)_(?![A-Za-z0-9_])")) { ts, m, _ in
            addFontTrait(.italic, to: ts, in: m.range)
        },
        Rule(regex: r("`[^`\\n]+`")) { ts, m, _ in
            ts.addAttribute(.backgroundColor, value: Theme.codeBackgroundColor, range: m.range)
            ts.addAttribute(.font, value: Theme.codeFont, range: m.range)
        },
        Rule(regex: r("~~(?!\\s)[^~\\n]+?(?<!\\s)~~")) { ts, m, _ in
            ts.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: m.range)
        },
        Rule(regex: r("\\[([^\\]\\n]+)\\]\\(([^)\\n]+)\\)")) { ts, m, _ in
            let label = m.range(at: 1)
            let url = m.range(at: 2)
            if label.location != NSNotFound {
                ts.addAttribute(.foregroundColor, value: Theme.linkColor, range: label)
                ts.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: label)
            }
            if url.location != NSNotFound {
                ts.addAttribute(.foregroundColor, value: Theme.mutedColor, range: url)
            }
        },
        Rule(regex: r("^[ \\t]*[-*+][ \\t]+", options: [.anchorsMatchLines])) { ts, m, map in
            let level = map.governingLevel(at: m.range.location)
            ts.addAttribute(.foregroundColor, value: Theme.headingColor(level: level), range: m.range)
        },
        Rule(regex: r("^[ \\t]*\\d+[.)][ \\t]+", options: [.anchorsMatchLines])) { ts, m, map in
            let level = map.governingLevel(at: m.range.location)
            ts.addAttribute(.foregroundColor, value: Theme.headingColor(level: level), range: m.range)
        },
        Rule(regex: r("^[ \\t]*>.*$", options: [.anchorsMatchLines])) { ts, m, _ in
            ts.addAttribute(.foregroundColor, value: Theme.mutedColor, range: m.range)
            addFontTrait(.italic, to: ts, in: m.range)
        },
        Rule(regex: r("^[ \\t]*(-{3,}|\\*{3,}|_{3,})[ \\t]*$", options: [.anchorsMatchLines])) { ts, m, _ in
            ts.addAttribute(.foregroundColor, value: Theme.mutedColor, range: m.range)
        }
    ]

    static func addFontTrait(_ trait: NSFontDescriptor.SymbolicTraits,
                             to ts: NSTextStorage,
                             in range: NSRange) {
        var mask: NSFontTraitMask = []
        if trait.contains(.bold) { mask.insert(.boldFontMask) }
        if trait.contains(.italic) { mask.insert(.italicFontMask) }
        guard !mask.isEmpty else { return }
        let manager = NSFontManager.shared
        ts.enumerateAttribute(.font, in: range, options: []) { value, subRange, _ in
            guard let existing = value as? NSFont else { return }
            let combined = manager.convert(existing, toHaveTrait: mask)
            ts.addAttribute(.font, value: combined, range: subRange)
        }
    }

    static func applyHighlighting(to ts: NSTextStorage, in range: NSRange, fencedSpans: [NSRange], frontMatter: NSRange?, sectionMap: SectionMap) {
        guard range.length > 0 else { return }

        ts.removeAttribute(.font, range: range)
        ts.removeAttribute(.foregroundColor, range: range)
        ts.removeAttribute(.backgroundColor, range: range)
        ts.removeAttribute(.underlineStyle, range: range)
        ts.removeAttribute(.strikethroughStyle, range: range)
        ts.addAttribute(.font, value: Theme.editorFont, range: range)
        ts.addAttribute(.foregroundColor, value: Theme.textColor, range: range)
        ts.addAttribute(.paragraphStyle, value: Theme.bodyParagraphStyle, range: range)

        for span in fencedSpans {
            let intersect = NSIntersectionRange(span, range)
            if intersect.length > 0 {
                ts.addAttribute(.foregroundColor, value: Theme.mutedColor, range: intersect)
                ts.addAttribute(.backgroundColor, value: Theme.codeBackgroundColor, range: intersect)
                ts.addAttribute(.font, value: Theme.codeFont, range: intersect)
            }
        }

        // Front matter reads as muted metadata: foreground only, no code background.
        if let fm = frontMatter {
            let intersect = NSIntersectionRange(fm, range)
            if intersect.length > 0 {
                ts.addAttribute(.foregroundColor, value: Theme.mutedColor, range: intersect)
            }
        }

        let excluded = frontMatter.map { fencedSpans + [$0] } ?? fencedSpans
        let source = ts.string
        for rule in inlineRules {
            rule.regex.enumerateMatches(in: source, options: [], range: range) { match, _, _ in
                guard let m = match else { return }
                if intersectsAny(m.range, ranges: excluded) { return }
                rule.apply(ts, m, sectionMap)
            }
        }
    }

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

    static func intersectsAny(_ range: NSRange, ranges: [NSRange]) -> Bool {
        for r in ranges where NSIntersectionRange(r, range).length > 0 { return true }
        return false
    }

    /// A leading YAML (`---`) or TOML (`+++`) front-matter block. Recognized only
    /// when the document's first line is exactly the delimiter and a matching
    /// closing delimiter line appears on a later line (content between the
    /// delimiters is not validated). Returns the block span (from index 0 through
    /// the end of the closing delimiter line) or nil.
    static func frontMatterSpan(in nsString: NSString, fullRange: NSRange) -> NSRange? {
        guard nsString.length > 0 else { return nil }
        var lineStart = 0, lineEnd = 0, contentsEnd = 0
        nsString.getLineStart(&lineStart, end: &lineEnd, contentsEnd: &contentsEnd,
                              for: NSRange(location: 0, length: 0))
        let firstLine = nsString.substring(with: NSRange(location: 0, length: contentsEnd))
        let delimiter: String
        if firstLine == "---" { delimiter = "---" }
        else if firstLine == "+++" { delimiter = "+++" }
        else { return nil }
        guard lineEnd > 0, lineEnd < nsString.length else { return nil }
        var idx = lineEnd
        while idx < nsString.length {
            var ls = 0, le = 0, ce = 0
            nsString.getLineStart(&ls, end: &le, contentsEnd: &ce, for: NSRange(location: idx, length: 0))
            let line = nsString.substring(with: NSRange(location: ls, length: ce - ls))
            if line == delimiter {
                return NSRange(location: 0, length: le)
            }
            guard le > ls else { break }
            idx = le
        }
        return nil
    }

    static let taskListPattern: NSRegularExpression = r(
        "^[ \\t]*[-*+][ \\t]+(\\[[ xX]\\])[ \\t]+",
        options: [.anchorsMatchLines]
    )

    static func taskCheckboxRanges(in textStorage: NSTextStorage) -> [NSRange] {
        let nsString = textStorage.string as NSString
        let full = NSRange(location: 0, length: nsString.length)
        var ranges: [NSRange] = []
        taskListPattern.enumerateMatches(in: nsString as String, options: [], range: full) { match, _, _ in
            guard let m = match else { return }
            let bracket = m.range(at: 1)
            if bracket.location != NSNotFound {
                ranges.append(bracket)
            }
        }
        return ranges
    }
}
