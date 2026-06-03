import Foundation

/// Pure word and character counting for the editor's optional status bar.
enum WordCount {
    struct Stats: Equatable {
        let words: Int
        let characters: Int
    }

    /// Count words via Unicode word boundaries (handles punctuation, whitespace
    /// runs, and CJK), and characters as grapheme clusters. O(n): the caller
    /// debounces so this does not run on every keystroke.
    static func stats(for text: String) -> Stats {
        var words = 0
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex,
                                 options: [.byWords, .localized]) { _, _, _, _ in
            words += 1
        }
        return Stats(words: words, characters: text.count)
    }

    /// Estimated silent reading time in whole minutes at a conservative 200 wpm.
    /// Returns 0 for an empty document, otherwise at least 1.
    static func readingMinutes(words: Int, wpm: Int = 200) -> Int {
        guard words > 0 else { return 0 }
        return max(1, Int((Double(words) / Double(wpm)).rounded(.up)))
    }
}

/// The "show the word-count bar" preference. Read via a direct UserDefaults read
/// (not @AppStorage, which does not reliably propagate across DocumentGroup
/// windows in MacMD), and broadcast on change so open document windows update
/// without a relaunch.
enum WordCountPref {
    static let key = "showWordCount"
    static let didChange = Notification.Name("MacMDWordCountPrefDidChange")

    static var isOn: Bool { UserDefaults.standard.bool(forKey: key) }

    static func set(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: key)
        NotificationCenter.default.post(name: didChange, object: nil)
    }
}
