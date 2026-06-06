import Foundation

/// The editor insertion-point style. `.bar` is the native thin caret (default).
enum CursorStyle: String, CaseIterable, Sendable {
    case bar, block, underline

    var displayName: String {
        switch self {
        case .bar: return "Bar"
        case .block: return "Block"
        case .underline: return "Underline"
        }
    }
}

/// Pure caret geometry, separated from drawing so it is unit-testable.
enum CursorGeometry {
    /// The block caret's width: the measured glyph advance when positive, else
    /// the fallback (a space's advance) so an end-of-line or empty-line caret
    /// still shows a full cell.
    static func blockWidth(glyphWidth: CGFloat, fallback: CGFloat) -> CGFloat {
        glyphWidth > 0 ? glyphWidth : fallback
    }
}
