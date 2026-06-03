import SwiftUI

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

/// A thin, unobtrusive status bar shown under the editor when the preference is
/// on. Recomputes the count on a 300ms debounce off the main actor.
struct WordCountBar: View {
    let text: String
    @State private var stats = WordCount.Stats(words: 0, characters: 0)
    @State private var hasComputed = false

    var body: some View {
        HStack {
            Spacer()
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .top) { Divider() }
        .task(id: text) {
            // Compute the first value eagerly so the bar never flashes "0 words"
            // when it appears over an existing document, then debounce later edits.
            // .task(id:) cancels and restarts this whenever `text` changes. The
            // closure is non-throwing, so try? swallows the CancellationError that
            // Task.sleep throws on cancellation; the isCancelled guards bail before
            // writing so a stale in-flight result cannot overwrite a newer edit.
            if hasComputed {
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled else { return }
            }
            let snapshot = text
            let computed = await Task.detached { WordCount.stats(for: snapshot) }.value
            guard !Task.isCancelled else { return }
            stats = computed
            hasComputed = true
        }
    }

    private var label: String {
        let w = stats.words
        let wordPart = "\(w.formatted()) \(w == 1 ? "word" : "words")"
        guard w >= 200 else { return wordPart }
        let minutes = WordCount.readingMinutes(words: w)
        return "\(wordPart) - about \(minutes) min read"
    }
}
