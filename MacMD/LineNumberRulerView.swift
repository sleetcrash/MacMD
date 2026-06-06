import AppKit

/// A line-number gutter shown only in Plain (formatting-off) mode. Numbers align
/// to logical lines; a wrapped logical line numbers only its first visual
/// fragment (code-editor convention). Reads font + colors from Theme. Adapted
/// from the standard NSTextView line-number ruler pattern.
final class LineNumberRulerView: NSRulerView {
    init(scrollView: NSScrollView, textView: NSTextView) {
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 40
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private var numberFont: NSFont {
        .monospacedSystemFont(ofSize: max(9, Theme.editorFontSize - 2), weight: .regular)
    }

    /// Recompute the gutter width from the document's line count so the widest
    /// number always fits. Call on text change and on entering Plain mode.
    func updateThickness() {
        guard let tv = clientView as? NSTextView else { return }
        let ns = tv.string as NSString
        let lines = LineNumbering.lineNumber(forCharacterIndex: ns.length, in: ns)
        let digits = max(2, String(lines).count)
        let sample = String(repeating: "9", count: digits) as NSString
        let width = sample.size(withAttributes: [.font: numberFont]).width
        let newThickness = ceil(width) + 12
        if abs(newThickness - ruleThickness) > 0.5 { ruleThickness = newThickness }
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let tv = clientView as? NSTextView,
              let lm = tv.layoutManager,
              let tc = tv.textContainer else { return }

        NSColor.textBackgroundColor.setFill()
        rect.fill()

        let ns = tv.string as NSString
        let inset = tv.textContainerInset.height
        let relativePoint = convert(NSPoint.zero, from: tv)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: numberFont,
            .foregroundColor: Theme.mutedColor
        ]

        let draw: (Int, CGFloat) -> Void = { number, yInTextView in
            let s = "\(number)" as NSString
            let size = s.size(withAttributes: attrs)
            let x = self.ruleThickness - size.width - 6
            s.draw(at: NSPoint(x: x, y: relativePoint.y + yInTextView + inset), withAttributes: attrs)
        }

        // Empty document: a single "1" on the trailing empty fragment.
        if ns.length == 0 {
            draw(1, lm.extraLineFragmentRect.minY)
            return
        }

        let visibleGlyphs = lm.glyphRange(forBoundingRect: tv.visibleRect, in: tc)
        let firstChar = lm.characterIndexForGlyph(at: visibleGlyphs.location)
        var lineNumber = LineNumbering.lineNumber(forCharacterIndex: firstChar, in: ns)

        var glyphIndex = visibleGlyphs.location
        let end = NSMaxRange(visibleGlyphs)
        while glyphIndex < end {
            let charIndex = lm.characterIndexForGlyph(at: glyphIndex)
            let lineCharRange = ns.lineRange(for: NSRange(location: charIndex, length: 0))
            let lineGlyphRange = lm.glyphRange(forCharacterRange: lineCharRange, actualCharacterRange: nil)
            // Number the first visual fragment of this logical line; advancing to
            // the end of the logical line's glyphs skips wrapped continuation rows.
            var effective = NSRange(location: 0, length: 0)
            let fragRect = lm.lineFragmentRect(forGlyphAt: lineGlyphRange.location,
                                               effectiveRange: &effective,
                                               withoutAdditionalLayout: true)
            draw(lineNumber, fragRect.minY)
            lineNumber += 1
            glyphIndex = NSMaxRange(lineGlyphRange)
        }

        // Trailing empty line (document ends with a newline) gets the next number.
        if lm.extraLineFragmentTextContainer != nil {
            draw(lineNumber, lm.extraLineFragmentRect.minY)
        }
    }
}
