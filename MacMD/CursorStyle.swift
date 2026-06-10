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

    /// The underline caret's rect: spans the character cell like the block
    /// (same width rule) but only `thickness` points tall, sitting on the
    /// cell's bottom edge. AppKit's incoming rect is the thin bar; without the
    /// width rule the underline degenerates to a ~1pt dot.
    static func underlineRect(caret: CGRect, glyphWidth: CGFloat, fallback: CGFloat,
                              thickness: CGFloat = 2) -> CGRect {
        CGRect(x: caret.minX,
               y: caret.maxY - thickness,
               width: blockWidth(glyphWidth: glyphWidth, fallback: fallback),
               height: thickness)
    }
}

/// Stops and restores the caret blink cleanly. AppKit's legacy caret path
/// (active whenever `drawInsertionPoint` is overridden) reads its blink on/off
/// periods from the `NSTextInsertionPointBlinkPeriod(On|Off)` defaults when the
/// caret timer (re)starts. Registering an effectively-infinite "on" period in
/// the VOLATILE registration domain keeps the caret steady without fighting the
/// timer pass-by-pass (the old force-on approach broke move-erases and caused
/// ghost carets) and without persisting anything to the user's real defaults.
enum CaretBlink {
    private static let onKey = "NSTextInsertionPointBlinkPeriodOn"
    private static let offKey = "NSTextInsertionPointBlinkPeriodOff"

    static func apply(_ blink: Bool) {
        var registration = UserDefaults.standard.volatileDomain(forName: UserDefaults.registrationDomain)
        if blink {
            registration.removeValue(forKey: onKey)
            registration.removeValue(forKey: offKey)
        } else {
            registration[onKey] = 1.0e10   // stay on ~forever once shown
            registration[offKey] = 1.0     // if ever caught off, recover at once
        }
        UserDefaults.standard.setVolatileDomain(registration, forName: UserDefaults.registrationDomain)
    }
}
