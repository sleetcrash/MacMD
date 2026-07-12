import AppKit

/// The editor's line-number gutter: a non-scrolling NSView pinned to the left
/// edge of the editor's scroll view, drawing 1-based logical line numbers aligned
/// to the text view's visible line fragments. Shown in both Styled and Plain modes
/// per LineNumbersPref; the text view reserves room by widening its left
/// textContainerInset. NOT an
/// NSRulerView - the ruler tiling does not inset MacMD's SwiftUI-hosted,
/// autoresizing NSTextView, so glyphs failed to paint. This view only draws,
/// synced to the clip bounds; it never participates in clip tiling.
final class LineNumberGutterView: NSView {
    weak var textView: ClickableTextView?

    /// Total logical line count, set by the Coordinator on text changes. Drives
    /// the gutter width and the trailing empty-line number so neither rescans the
    /// whole document on every scroll.
    var lineCount = 1

    /// The strip's fill, set by the Coordinator: the custom editor background
    /// when one is active, else the appearance-driven default. Keeps the gutter
    /// from reading as a mismatched stripe beside a custom-colored editor.
    var backgroundColor: NSColor = .textBackgroundColor

    /// Left padding before the numbers, and the gap between numbers and body text.
    static let leftPadding: CGFloat = 6
    static let textGap: CGFloat = 8
    /// Reserve room for at least two digits so the gutter does not jump 9 -> 10.
    static let minDigits = 2

    override var isFlipped: Bool { true }   // match the text view's flipped coords

    init(textView: ClickableTextView) {
        self.textView = textView
        super.init(frame: .zero)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Slightly-smaller, always-monospace number font (monospace keeps the
    /// right-aligned digits steady under a proportional body font).
    private var numberFont: NSFont {
        .monospacedSystemFont(ofSize: max(9, Theme.editorFontSize - 2), weight: .regular)
    }
    private var numberAttributes: [NSAttributedString.Key: Any] {
        [.font: numberFont, .foregroundColor: Theme.mutedColor]
    }

    /// Width for the widest line number in the WHOLE document plus padding, so the
    /// gutter width is stable while scrolling (does not jiggle per visible range).
    func requiredWidth() -> CGFloat {
        let digits = max(Self.minDigits, String(max(1, lineCount)).count)
        let sample = String(repeating: "0", count: digits) as NSString
        let textWidth = sample.size(withAttributes: numberAttributes).width
        return ceil(Self.leftPadding + textWidth + Self.textGap)
    }

    override func draw(_ dirtyRect: NSRect) {
        backgroundColor.setFill()
        bounds.fill()

        guard let textView,
              let lm = textView.layoutManager,
              let tc = textView.textContainer,
              let ts = textView.textStorage else { return }
        let ns = ts.string as NSString
        let containerOriginY = textView.textContainerOrigin.y
        let visible = textView.visibleRect
        let glyphRange = lm.glyphRange(forBoundingRect: visible, in: tc)

        // Seed the first visible fragment's logical line once (O(firstIndex)),
        // then increment per logical line - so each visible fragment is O(1)
        // instead of rescanning newlines from the document start.
        var line = -1
        var first = true
        var lastDrawn = -1
        lm.enumerateLineFragments(forGlyphRange: glyphRange) { rect, _, _, fragmentGlyphRange, _ in
            let charRange = lm.characterRange(forGlyphRange: fragmentGlyphRange, actualGlyphRange: nil)
            // A fragment starts a logical line iff it is at index 0 or the char
            // before it is a newline. Continuation fragments of a wrapped line are
            // skipped (blank), per the code-editor convention.
            let isLineStart = charRange.location == 0
                || (charRange.location <= ns.length && ns.character(at: charRange.location - 1) == 0x000A)
            if first {
                line = LineNumbering.lineNumber(forCharacterIndex: charRange.location, in: ns)
                first = false
            } else if isLineStart {
                line += 1
            }
            guard isLineStart else { return }
            self.draw(number: line, fragmentRect: rect, containerOriginY: containerOriginY, visibleMinY: visible.minY)
            lastDrawn = line
        }

        // Trailing empty line (doc ends with '\n') or an empty document: enumerate
        // emits no fragment for it, so use the extra line fragment rect. Its number
        // is the total line count (already cached, no rescan).
        let extra = lm.extraLineFragmentRect
        if extra.height > 0 {
            let yTextView = extra.minY + containerOriginY
            if yTextView + extra.height >= visible.minY && yTextView <= visible.maxY {
                if lineCount != lastDrawn {
                    self.draw(number: lineCount, fragmentRect: extra, containerOriginY: containerOriginY, visibleMinY: visible.minY)
                }
            }
        }
    }

    private func draw(number n: Int, fragmentRect: NSRect, containerOriginY: CGFloat, visibleMinY: CGFloat) {
        let str = String(n) as NSString
        let attrs = numberAttributes
        let size = str.size(withAttributes: attrs)
        let yInGutter = fragmentRect.minY + containerOriginY - visibleMinY
        let y = yInGutter + (fragmentRect.height - size.height) / 2   // center within the line
        let x = bounds.width - Self.textGap - size.width             // right-align
        str.draw(at: NSPoint(x: x, y: y), withAttributes: attrs)
    }
}
