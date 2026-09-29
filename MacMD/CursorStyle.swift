import AppKit

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

/// Holds the caret steady when blink is off. AppKit's legacy caret path
/// (active whenever `drawInsertionPoint` is overridden) blinks on its own timer
/// and, on macOS 15, ignores the `NSTextInsertionPointBlinkPeriod(On|Off)`
/// defaults even when passed at launch (measured: default-rate blinking
/// either way). Restarting that timer always resumes at "on", so while blink
/// is off the focused editor's caret is restarted faster than its on phase
/// (about half a second) can expire. Forcing "on" inside the draw pass
/// instead broke move-erases and left ghost carets.
@MainActor
enum CaretBlink {
    private static var steadyTimer: Timer?

    static func apply(_ blink: Bool) {
        if blink {
            steadyTimer?.invalidate()
            steadyTimer = nil
        } else if steadyTimer == nil {
            let timer = Timer(timeInterval: 0.2, repeats: true) { _ in
                MainActor.assumeIsolated {
                    (NSApp.keyWindow?.firstResponder as? ClickableTextView)?
                        .updateInsertionPointStateAndRestartTimer(true)
                }
            }
            // Common modes, so the caret also holds during scroll and drag tracking.
            RunLoop.main.add(timer, forMode: .common)
            steadyTimer = timer
        }
    }
}
