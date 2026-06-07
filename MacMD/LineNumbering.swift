import Foundation

/// Pure character-index -> 1-based line number, separated from the gutter view so
/// it is unit-testable without AppKit drawing.
enum LineNumbering {
    /// One plus the number of newline (`\n`) characters strictly before `index`.
    /// `index` is clamped to `[0, string.length]`.
    static func lineNumber(forCharacterIndex index: Int, in string: NSString) -> Int {
        let clamped = max(0, min(index, string.length))
        var count = 1
        var i = 0
        while i < clamped {
            if string.character(at: i) == 0x000A { count += 1 }
            i += 1
        }
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
}
