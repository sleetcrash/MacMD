import AppKit

/// Plain-mode line-number gutter: a non-scrolling NSView pinned to the left edge
/// of the editor's scroll view, drawing 1-based logical line numbers aligned to
/// the text view's visible line fragments. Shown only when formatting is OFF; the
/// text view reserves room by widening its left textContainerInset. NOT an
/// NSRulerView - the ruler tiling does not inset MacMD's SwiftUI-hosted,
/// autoresizing NSTextView, so glyphs failed to paint. This view only draws,
/// synced to the clip bounds; it never participates in clip tiling.
final class LineNumberGutterView: NSView {
    weak var textView: ClickableTextView?

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
        let totalLines: Int
        if let ts = textView?.textStorage {
            let ns = ts.string as NSString
            totalLines = LineNumbering.lineNumber(forCharacterIndex: ns.length, in: ns)
        } else {
            totalLines = 0
        }
        let digits = max(Self.minDigits, String(max(1, totalLines)).count)
        let sample = String(repeating: "0", count: digits) as NSString
        let textWidth = sample.size(withAttributes: numberAttributes).width
        return ceil(Self.leftPadding + textWidth + Self.textGap)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        bounds.fill()

        guard let textView,
              let lm = textView.layoutManager,
              let tc = textView.textContainer,
              let ts = textView.textStorage else { return }
        let ns = ts.string as NSString
        let containerOriginY = textView.textContainerOrigin.y
        let visible = textView.visibleRect
        let glyphRange = lm.glyphRange(forBoundingRect: visible, in: tc)

        var lastDrawn = -1
        lm.enumerateLineFragments(forGlyphRange: glyphRange) { rect, _, _, fragmentGlyphRange, _ in
            let charRange = lm.characterRange(forGlyphRange: fragmentGlyphRange, actualGlyphRange: nil)
            // A fragment starts a logical line iff it is at index 0 or the char
            // before it is a newline. Continuation fragments of a wrapped line are
            // skipped (blank), per the code-editor convention.
            let isLineStart = charRange.location == 0
                || (charRange.location <= ns.length && ns.character(at: charRange.location - 1) == 0x000A)
            guard isLineStart else { return }
            let n = LineNumbering.lineNumber(forCharacterIndex: charRange.location, in: ns)
            self.draw(number: n, fragmentRect: rect, containerOriginY: containerOriginY, visibleMinY: visible.minY)
            lastDrawn = n
        }

        // Trailing empty line (doc ends with '\n') or an empty document: enumerate
        // emits no fragment for it, so use the extra line fragment rect.
        let extra = lm.extraLineFragmentRect
        if extra.height > 0 {
            let yTextView = extra.minY + containerOriginY
            if yTextView + extra.height >= visible.minY && yTextView <= visible.maxY {
                let n = LineNumbering.lineNumber(forCharacterIndex: ns.length, in: ns)
                if n != lastDrawn {
                    self.draw(number: n, fragmentRect: extra, containerOriginY: containerOriginY, visibleMinY: visible.minY)
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
