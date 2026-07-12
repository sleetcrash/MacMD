import Foundation

/// Pure character-index -> 1-based line number, separated from the gutter view so
/// it is unit-testable without AppKit drawing.
enum LineNumbering {
    /// One plus the number of newline (`\n`) characters strictly before `index`.
    /// `index` is clamped to `[0, string.length]`.
    static func lineNumber(forCharacterIndex index: Int, in string: NSString) -> Int {
        let clamped = max(0, min(index, string.length))
        guard clamped > 0 else { return 1 }
        // Copy the prefix once and scan it in a tight loop, rather than paying a
        // per-character `character(at:)` bridge cost. The gutter seeds this on
        // every scroll frame, so at the bottom of a large file the old per-char
        // path stalled the main thread; this keeps it sub-frame.
        var prefix = [unichar](repeating: 0, count: clamped)
        string.getCharacters(&prefix, range: NSRange(location: 0, length: clamped))
        var count = 1
        for unit in prefix where unit == 0x000A { count += 1 }
        return count
    }

    /// Total 1-based logical line count (newline count + 1) via a fast contiguous
    /// UTF-8 scan, for the gutter width and the trailing empty-line number where
    /// the per-character `NSString` path would be needlessly slow on a large
    /// document. Equivalent to `lineNumber(forCharacterIndex: length, in:)`.
    static func lineCount(in string: String) -> Int {
        var count = 1
        for byte in string.utf8 where byte == 0x000A { count += 1 }
        return count
    }

    /// The character index of the START of a 1-based line: the inverse of
    /// `lineNumber(forCharacterIndex:in:)`, for preview-to-editor scroll sync.
    /// A line past the end clamps to the last line's start. O(line) via
    /// getLineStart hops; no whole-document copy per call.
    static func characterIndex(forLine line: Int, in string: NSString) -> Int {
        guard line > 1, string.length > 0 else { return 0 }
        var current = 1
        var start = 0
        while current < line {
            var lineEnd = 0
            string.getLineStart(nil, end: &lineEnd, contentsEnd: nil,
                                for: NSRange(location: start, length: 0))
            guard lineEnd > start else { break }
            if lineEnd >= string.length {
                // A document ending in a newline has one trailing empty line
                // starting at the very end; anything beyond clamps to it.
                let last = string.character(at: string.length - 1)
                if last == 0x000A || last == 0x000D { return string.length }
                break
            }
            start = lineEnd
            current += 1
        }
        return start
    }
}
