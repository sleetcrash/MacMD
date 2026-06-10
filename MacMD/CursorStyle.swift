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
/// caret timer (re)starts. Registering a very long "on" period in the VOLATILE
/// registration domain keeps the caret steady without fighting the timer
/// pass-by-pass (the old force-on approach broke move-erases and caused ghost
/// carets) and without persisting anything to the user's real defaults.
@MainActor
enum CaretBlink {
    private static let onKey = "NSTextInsertionPointBlinkPeriodOn"
    private static let offKey = "NSTextInsertionPointBlinkPeriodOff"
    /// Whether our keys are currently registered. The registration domain is
    /// only ever touched to flip between the two states: a wholesale
    /// setVolatileDomain round-trip can clobber AppKit's own registered
    /// defaults (observed: after an apply(true) round-trip at launch the blink
    /// timer never sent its off passes again), so blink-on with nothing to
    /// undo must be a pure no-op.
    private static var registered = false

    static func apply(_ blink: Bool) {
        guard blink == registered else { return }
        var registration = UserDefaults.standard.volatileDomain(forName: UserDefaults.registrationDomain)
        if blink {
            registration.removeValue(forKey: onKey)
            registration.removeValue(forKey: offKey)
            registered = false
        } else {
            // ~3.3 minutes on, instant recovery if ever caught off. Any
            // keystroke or selection change restarts the cycle at "on", so the
            // caret reads as steady. The values must stay well below 2^31: a
            // huge period (1e10) made the post-move re-show never fire, which
            // VANISHED the caret after arrow moves.
            registration[onKey] = 200000.0
            registration[offKey] = 1.0
            registered = true
        }
        UserDefaults.standard.setVolatileDomain(registration, forName: UserDefaults.registrationDomain)
    }
}
