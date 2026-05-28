import AppKit

final class MarkdownHighlighter: NSObject, NSTextStorageDelegate {

    var isSuppressed = false
    private var lastFenceLineStarts: [Int] = []

    private struct Rule {
        let regex: NSRegularExpression
        let apply: (NSTextStorage, NSTextCheckingResult) -> Void
    }

    private static func r(_ pattern: String, options: NSRegularExpression.Options = []) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: options)
    }

    private static let fencePattern: NSRegularExpression = r("^[ \\t]*```[^\\n]*$", options: [.anchorsMatchLines])

    private static let inlineRules: [Rule] = [
        Rule(regex: r("^(#{1,6})[ \\t]+.+$", options: [.anchorsMatchLines])) { ts, m in
            let full = m.range
            let hashes = m.range(at: 1)
            let level = min(6, max(1, hashes.length))
            ts.addAttribute(.font, value: Theme.headingFont(level: level), range: full)
            ts.addAttribute(.foregroundColor, value: Theme.accentColor, range: full)
        },
        Rule(regex: r("\\*\\*(?!\\s)[^\\n]+?(?<!\\s)\\*\\*")) { ts, m in
            addFontTrait(.bold, to: ts, in: m.range)
        },
        Rule(regex: r("(?<![A-Za-z0-9_])__(?!\\s)[^\\n]+?(?<!\\s)__(?![A-Za-z0-9_])")) { ts, m in
            addFontTrait(.bold, to: ts, in: m.range)
        },
        Rule(regex: r("(?<![\\*A-Za-z0-9])\\*(?!\\s)[^*\\n]+(?<!\\s)\\*(?![\\*A-Za-z0-9])")) { ts, m in
            addFontTrait(.italic, to: ts, in: m.range)
        },
        Rule(regex: r("(?<![A-Za-z0-9_])_(?!\\s)[^_\\n]+(?<!\\s)_(?![A-Za-z0-9_])")) { ts, m in
            addFontTrait(.italic, to: ts, in: m.range)
        },
        Rule(regex: r("`[^`\\n]+`")) { ts, m in
            ts.addAttribute(.backgroundColor, value: Theme.codeBackgroundColor, range: m.range)
        },
        Rule(regex: r("\\[([^\\]\\n]+)\\]\\(([^)\\n]+)\\)")) { ts, m in
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
        Rule(regex: r("^[ \\t]*[-*+][ \\t]+", options: [.anchorsMatchLines])) { ts, m in
            ts.addAttribute(.foregroundColor, value: Theme.accentColor, range: m.range)
        },
        Rule(regex: r("^[ \\t]*\\d+\\.[ \\t]+", options: [.anchorsMatchLines])) { ts, m in
            ts.addAttribute(.foregroundColor, value: Theme.accentColor, range: m.range)
        },
        Rule(regex: r("^[ \\t]*>.*$", options: [.anchorsMatchLines])) { ts, m in
            ts.addAttribute(.foregroundColor, value: Theme.mutedColor, range: m.range)
            addFontTrait(.italic, to: ts, in: m.range)
        },
        Rule(regex: r("^[ \\t]*(-{3,}|\\*{3,}|_{3,})[ \\t]*$", options: [.anchorsMatchLines])) { ts, m in
            ts.addAttribute(.foregroundColor, value: Theme.mutedColor, range: m.range)
        }
    ]

    private static func addFontTrait(_ trait: NSFontDescriptor.SymbolicTraits,
                                     to ts: NSTextStorage,
                                     in range: NSRange) {
        let mask: NSFontTraitMask
        if trait.contains(.bold) {
            mask = .boldFontMask
        } else if trait.contains(.italic) {
            mask = .italicFontMask
        } else {
            return
        }
        let manager = NSFontManager.shared
        ts.enumerateAttribute(.font, in: range, options: []) { value, subRange, _ in
            guard let existing = value as? NSFont else { return }
            let combined = manager.convert(existing, toHaveTrait: mask)
            ts.addAttribute(.font, value: combined, range: subRange)
        }
    }

    func textStorage(_ textStorage: NSTextStorage,
                     didProcessEditing editedMask: NSTextStorageEditActions,
                     range editedRange: NSRange,
                     changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters), !isSuppressed else { return }

        let nsString = textStorage.string as NSString
        let total = NSRange(location: 0, length: nsString.length)
        guard editedRange.location <= nsString.length else { return }

        let fenceLines = fenceLineRanges(in: nsString, fullRange: total)
        let currentFenceStarts = fenceLines.map { $0.location }
        let fencesChanged = currentFenceStarts != lastFenceLineStarts
        lastFenceLineStarts = currentFenceStarts

        let codeSpans = spansFromFences(fenceLines, fullRange: total)

        if fencesChanged {
            applyHighlighting(to: textStorage, in: total, fencedSpans: codeSpans)
            return
        }

        let paragraph = nsString.paragraphRange(for: editedRange)
        let targetRange: NSRange
        if let containing = codeSpans.first(where: { NSLocationInRange(paragraph.location, $0) || NSIntersectionRange($0, paragraph).length > 0 }) {
            targetRange = containing
        } else {
            targetRange = paragraph
        }

        applyHighlighting(to: textStorage, in: targetRange, fencedSpans: codeSpans)
    }

    func rehighlightAll(_ textStorage: NSTextStorage) {
        let nsString = textStorage.string as NSString
        let full = NSRange(location: 0, length: nsString.length)
        let fenceLines = fenceLineRanges(in: nsString, fullRange: full)
        lastFenceLineStarts = fenceLines.map { $0.location }
        let spans = spansFromFences(fenceLines, fullRange: full)
        applyHighlighting(to: textStorage, in: full, fencedSpans: spans)
    }

    private func applyHighlighting(to ts: NSTextStorage, in range: NSRange, fencedSpans: [NSRange]) {
        guard range.length > 0 else { return }

        ts.removeAttribute(.font, range: range)
        ts.removeAttribute(.foregroundColor, range: range)
        ts.removeAttribute(.backgroundColor, range: range)
        ts.removeAttribute(.underlineStyle, range: range)
        ts.addAttribute(.font, value: Theme.editorFont, range: range)
        ts.addAttribute(.foregroundColor, value: Theme.textColor, range: range)
        ts.addAttribute(.paragraphStyle, value: Theme.bodyParagraphStyle, range: range)

        for span in fencedSpans {
            let intersect = NSIntersectionRange(span, range)
            if intersect.length > 0 {
                ts.addAttribute(.foregroundColor, value: Theme.mutedColor, range: intersect)
                ts.addAttribute(.backgroundColor, value: Theme.codeBackgroundColor, range: intersect)
            }
        }

        let source = ts.string
        for rule in Self.inlineRules {
            rule.regex.enumerateMatches(in: source, options: [], range: range) { match, _, _ in
                guard let m = match else { return }
                if Self.intersectsAny(m.range, ranges: fencedSpans) { return }
                rule.apply(ts, m)
            }
        }
    }

    private func fenceLineRanges(in nsString: NSString, fullRange: NSRange) -> [NSRange] {
        var fences: [NSRange] = []
        Self.fencePattern.enumerateMatches(in: nsString as String, options: [], range: fullRange) { match, _, _ in
            if let m = match { fences.append(m.range) }
        }
        return fences
    }

    private func spansFromFences(_ fences: [NSRange], fullRange: NSRange) -> [NSRange] {
        var spans: [NSRange] = []
        var i = 0
        while i < fences.count {
            let open = fences[i]
            if i + 1 < fences.count {
                let close = fences[i + 1]
                let start = open.location
                let end = close.location + close.length
                spans.append(NSRange(location: start, length: end - start))
                i += 2
            } else {
                let start = open.location
                let end = fullRange.location + fullRange.length
                spans.append(NSRange(location: start, length: end - start))
                i += 1
            }
        }
        return spans
    }

    private static func intersectsAny(_ range: NSRange, ranges: [NSRange]) -> Bool {
        for r in ranges where NSIntersectionRange(r, range).length > 0 { return true }
        return false
    }
}
