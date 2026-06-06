import Foundation

/// Pure character-index -> 1-based line number, separated from the ruler view so
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
}
