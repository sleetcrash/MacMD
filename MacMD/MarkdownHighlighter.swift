import AppKit

@MainActor
final class MarkdownHighlighter: NSObject, @preconcurrency NSTextStorageDelegate {

    var isSuppressed = false
    var isDisabled = false
    private var lastFenceLines: [MarkdownParser.FenceLine] = []
    private var lastHeadingLines: [MarkdownParser.HeadingLine] = []
    private var lastFrontMatter: NSRange?

    func textStorage(_ textStorage: NSTextStorage,
                     didProcessEditing editedMask: NSTextStorageEditActions,
                     range editedRange: NSRange,
                     changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters), !isSuppressed, !isDisabled else { return }

        let nsString = textStorage.string as NSString
        let total = NSRange(location: 0, length: nsString.length)
        guard editedRange.location <= nsString.length else { return }

        let fenceLines = MarkdownParser.fenceLines(in: nsString, fullRange: total)
        let fencesChanged = fenceLines != lastFenceLines
        lastFenceLines = fenceLines

        let codeSpans = MarkdownParser.spansFromFences(fenceLines, fullRange: total)

        let frontMatter = MarkdownParser.frontMatterSpan(in: nsString, fullRange: total)
        let frontMatterChanged = frontMatter != lastFrontMatter
        lastFrontMatter = frontMatter

        let headings: [MarkdownParser.HeadingLine] = Theme.activeColoring == .off
            ? []
            : MarkdownParser.headingLines(in: nsString, fullRange: total)
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
        let fenceLines = MarkdownParser.fenceLines(in: nsString, fullRange: full)
        lastFenceLines = fenceLines
        let spans = MarkdownParser.spansFromFences(fenceLines, fullRange: full)
        let frontMatter = MarkdownParser.frontMatterSpan(in: nsString, fullRange: full)
        lastFrontMatter = frontMatter
        let headings: [MarkdownParser.HeadingLine] = Theme.activeColoring == .off
            ? []
            : MarkdownParser.headingLines(in: nsString, fullRange: full)
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

    static func sectionMap(from headings: [MarkdownParser.HeadingLine], excluding fencedSpans: [NSRange]) -> SectionMap {
        let usable = headings.filter { !MarkdownParser.intersectsAny($0.range, ranges: fencedSpans) }
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
        Rule(regex: MarkdownParser.headingPattern) { ts, m, _ in
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
        // Bounded, atomic inner runs so a single long line of `[a](` repeated
        // can't drive catastrophic O(n^2) backtracking (a real DoS, since the app
        // opens untrusted .md files). Same defense as the emphasis rules above.
        // Group 1 = label, group 2 = url.
        Rule(regex: r("\\[(?>([^\\]\\n]{1,1024}))\\]\\((?>([^)\\n]{1,2048}))\\)")) { ts, m, _ in
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

        let source = ts.string

        // Front matter reads as muted metadata: foreground only, no code background.
        // Under an active color scheme, keys (name:, description:, ...) pick up the
        // theme's H1 color so agent-file metadata reads at a glance; the Default
        // scheme keeps the whole block muted (the pre-2.1 look).
        if let fm = frontMatter {
            let intersect = NSIntersectionRange(fm, range)
            if intersect.length > 0 {
                ts.addAttribute(.foregroundColor, value: Theme.mutedColor, range: intersect)
                if Theme.activeColoring != .off {
                    frontMatterKeyPattern.enumerateMatches(in: source, options: [], range: intersect) { match, _, _ in
                        guard let key = match?.range(at: 1), key.location != NSNotFound else { return }
                        ts.addAttribute(.foregroundColor, value: Theme.headingColor(level: 1), range: key)
                    }
                }
            }
        }

        let excluded = frontMatter.map { fencedSpans + [$0] } ?? fencedSpans
        for rule in inlineRules {
            rule.regex.enumerateMatches(in: source, options: [], range: range) { match, _, _ in
                guard let m = match else { return }
                if MarkdownParser.intersectsAny(m.range, ranges: excluded) { return }
                rule.apply(ts, m, sectionMap)
            }
        }
    }

    /// A front-matter key line: optional indent, the key, a colon. Group 1 = key.
    static let frontMatterKeyPattern: NSRegularExpression = r(
        "^[ \\t]*([A-Za-z0-9_-]+):",
        options: [.anchorsMatchLines]
    )

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
