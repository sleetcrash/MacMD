import Foundation

/// Pure map from a character position to the level of the nearest preceding
/// heading. Used by the highlighter to color list markers with the color of
/// the section they sit under. A position before any heading governs at level
/// 1 (so markers above the first heading take the H1 color).
struct SectionMap {
    private let starts: [(location: Int, level: Int)]

    init(headings: [(location: Int, level: Int)]) {
        self.starts = headings.sorted { $0.location < $1.location }
    }

    /// Level of the nearest heading at or before `location`; 1 if none precedes.
    func governingLevel(at location: Int) -> Int {
        var result = 1
        for h in starts {
            if h.location <= location { result = h.level } else { break }
        }
        return result
    }
}
