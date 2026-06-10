import SwiftUI
import AppKit

struct MarkdownTextView: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat
    var fontFamily: FontFamily
    var coloring: Coloring
    var palette: Palette?
    var appearance: AppAppearance
    /// Non-nil = paint this fixed color instead of the appearance-driven
    /// `.textBackgroundColor`. `appearance` is then already the EFFECTIVE
    /// appearance derived from this color's luminance (see DocumentView), so
    /// text resolves readable against it.
    var customBackground: NSColor?
    var cursorStyle: CursorStyle
    var cursorBlink: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        Theme.setEditorFontSize(fontSize)
        Theme.setEditorFontFamily(fontFamily)
        Theme.setCursor(style: cursorStyle, blink: cursorBlink)
        Theme.setActiveTheme(coloring: coloring, palette: palette)
        let scrollView = ClickableTextView.scrollableClickableTextView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = customBackground ?? .textBackgroundColor

        guard let textView = scrollView.documentView as? ClickableTextView else {
            return scrollView
        }

        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsImageEditing = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = true
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.usesFontPanel = false
        textView.usesRuler = false
        textView.isRulerVisible = false
        textView.textContainerInset = NSSize(width: 24, height: 20)
        textView.font = Theme.editorFont
        textView.textColor = Theme.textColor
        textView.backgroundColor = customBackground ?? .textBackgroundColor
        textView.drawsBackground = true
        textView.insertionPointColor = Theme.accentColor
        textView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textView.isAutomaticTextCompletionEnabled = false

        if let container = textView.textContainer {
            container.widthTracksTextView = true
            container.lineFragmentPadding = 6
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = Theme.editorLineSpacing
        paragraph.defaultTabInterval = 28
        paragraph.tabStops = []
        textView.defaultParagraphStyle = paragraph
        textView.typingAttributes = [
            .font: Theme.editorFont,
            .foregroundColor: Theme.textColor,
            .paragraphStyle: paragraph
        ]

        textView.setAccessibilityLabel("Markdown editor")

        textView.delegate = context.coordinator
        textView.textStorage?.delegate = context.coordinator.highlighter
        textView.highlighter = context.coordinator.highlighter

        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView
        context.coordinator.customBackground = customBackground
        context.coordinator.loadInitial(text: text)
        context.coordinator.observeFormatting(textView: textView)
        context.coordinator.syncGutter()
        // Pick up a saved blink-off at launch: updateNSView's change check only
        // catches LATER pref changes, not the initial load.
        textView.refreshCaret()

        let initialAppearance = appearance
        DispatchQueue.main.async { [weak textView] in
            textView?.window?.appearance = initialAppearance.nsAppearance
        }

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        let sizeChanged = Theme.setEditorFontSize(fontSize)
        let familyChanged = Theme.setEditorFontFamily(fontFamily)
        if sizeChanged || familyChanged {
            context.coordinator.applyFontChange(to: textView)
        }
        if Theme.setActiveTheme(coloring: coloring, palette: palette) {
            context.coordinator.applyThemeChange(to: textView)
        }
        textView.window?.appearance = appearance.nsAppearance
        let background = customBackground ?? .textBackgroundColor
        if textView.backgroundColor != background {
            textView.backgroundColor = background
            nsView.backgroundColor = background
            context.coordinator.customBackground = customBackground
            context.coordinator.refreshGutter()
        }
        if Theme.setCursor(style: cursorStyle, blink: cursorBlink) {
            (textView as? ClickableTextView)?.refreshCaret()
        }
        if textView.string != text {
            context.coordinator.replace(textView: textView, with: text)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        weak var textView: NSTextView?
        let highlighter = MarkdownHighlighter()
        private var isUpdatingFromBinding = false
        private var hasLoaded = false
        private var isOverSoftSizeLimit = false
        private var formattingObserver: NSObjectProtocol?
        weak var scrollView: NSScrollView?
        private var gutter: LineNumberGutterView?
        private var clipObserver: NSObjectProtocol?
        private var cachedLineCount = 1
        /// Mirrors MarkdownTextView.customBackground so the gutter's strip can
        /// match the editor's painted background.
        var customBackground: NSColor?

        static let baseInsetWidth: CGFloat = 24
        static let insetHeight: CGFloat = 20

        init(text: Binding<String>) {
            self._text = text
        }

        func loadInitial(text: String) {
            guard !hasLoaded, let tv = textView, let ts = tv.textStorage else { return }
            hasLoaded = true
            cachedLineCount = LineNumbering.lineCount(in: text)
            isUpdatingFromBinding = true
            highlighter.isSuppressed = true
            ts.beginEditing()
            ts.replaceCharacters(in: NSRange(location: 0, length: ts.length), with: text)
            ts.endEditing()
            highlighter.isSuppressed = false
            isOverSoftSizeLimit = text.utf8.count >= MarkdownDocument.softSizeLimit
            let shouldHighlight = FormattingPref.shouldHighlight(showFormatting: FormattingPref.isOn,
                                                                 overSoftSizeLimit: isOverSoftSizeLimit)
            highlighter.isDisabled = !shouldHighlight
            if shouldHighlight {
                highlighter.rehighlightAll(ts)
            } else {
                highlighter.clearHighlighting(ts)
            }
            isUpdatingFromBinding = false
        }

        func replace(textView: NSTextView, with newText: String) {
            guard let ts = textView.textStorage else { return }
            let oldSelection = textView.selectedRange()
            isUpdatingFromBinding = true
            highlighter.isSuppressed = true
            ts.beginEditing()
            ts.replaceCharacters(in: NSRange(location: 0, length: ts.length), with: newText)
            ts.endEditing()
            highlighter.isSuppressed = false
            highlighter.rehighlightAll(ts)

            let newLength = (ts.string as NSString).length
            let location = min(oldSelection.location, newLength)
            let length = min(oldSelection.length, newLength - location)
            textView.setSelectedRange(NSRange(location: location, length: length))
            cachedLineCount = LineNumbering.lineCount(in: newText)
            refreshGutter()
            isUpdatingFromBinding = false
        }

        func applyFontChange(to textView: NSTextView) {
            guard let ts = textView.textStorage else { return }
            textView.typingAttributes[.font] = Theme.editorFont
            if highlighter.isDisabled {
                textView.font = Theme.editorFont
            } else {
                highlighter.rehighlightAll(ts)
            }
            refreshGutter()
        }

        func applyThemeChange(to textView: NSTextView) {
            guard let ts = textView.textStorage, !highlighter.isDisabled else { return }
            highlighter.rehighlightAll(ts)
        }

        /// React to a global Show Formatting change: flip styled<->plain with no
        /// document mutation.
        func applyFormattingChange(to textView: NSTextView) {
            guard let ts = textView.textStorage else { return }
            let show = FormattingPref.isOn
            let shouldHighlight = FormattingPref.shouldHighlight(showFormatting: show,
                                                                overSoftSizeLimit: isOverSoftSizeLimit)
            highlighter.isSuppressed = true
            highlighter.isDisabled = !shouldHighlight
            if shouldHighlight {
                highlighter.rehighlightAll(ts)
            } else {
                highlighter.clearHighlighting(ts)
                textView.font = Theme.editorFont
            }
            highlighter.isSuppressed = false
            syncGutter()
        }

        func observeFormatting(textView: NSTextView) {
            formattingObserver = NotificationCenter.default.addObserver(
                forName: FormattingPref.didChange, object: nil, queue: .main) { [weak self, weak textView] _ in
                guard let self, let textView else { return }
                MainActor.assumeIsolated { self.applyFormattingChange(to: textView) }
            }
        }

        // MARK: - Line-number gutter (Plain mode only)

        /// Install/remove the gutter and widen/restore the left inset to match the
        /// current FormattingPref. The gutter shows only when formatting is OFF
        /// (Plain). Restores the base 24pt inset in Styled mode so defaults are
        /// byte-identical to today.
        func syncGutter() {
            guard let tv = textView as? ClickableTextView, let scrollView else { return }
            if FormattingPref.isOn {
                gutter?.removeFromSuperview()
                gutter = nil
                if let clipObserver {
                    NotificationCenter.default.removeObserver(clipObserver)
                    self.clipObserver = nil
                }
                tv.textContainerInset = NSSize(width: Self.baseInsetWidth, height: Self.insetHeight)
            } else {
                if gutter == nil {
                    let v = LineNumberGutterView(textView: tv)
                    v.autoresizingMask = [.height]
                    scrollView.addSubview(v)
                    gutter = v
                    observeClipBounds(scrollView: scrollView)
                    // Re-lay out once the host has settled the frames (at first
                    // install the clip height can still be zero).
                    DispatchQueue.main.async { [weak self] in self?.refreshGutter() }
                }
                layoutGutter()
            }
        }

        /// Recompute gutter width, widen the text inset to reserve it, size the
        /// gutter to the viewport, and redraw.
        private func layoutGutter() {
            guard let g = gutter, let scrollView, let tv = textView as? ClickableTextView else { return }
            g.lineCount = cachedLineCount
            g.backgroundColor = customBackground ?? .textBackgroundColor
            let width = g.requiredWidth()
            tv.textContainerInset = NSSize(width: width, height: Self.insetHeight)
            g.frame = NSRect(x: 0, y: 0, width: width, height: scrollView.contentView.frame.height)
            g.needsDisplay = true
        }

        private func observeClipBounds(scrollView: NSScrollView) {
            let clip = scrollView.contentView
            clip.postsBoundsChangedNotifications = true
            clipObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification, object: clip, queue: .main) { [weak self] _ in
                guard let self else { return }
                MainActor.assumeIsolated {
                    if let g = self.gutter, let sv = self.scrollView {
                        g.frame.size.height = sv.contentView.frame.height
                    }
                    self.gutter?.needsDisplay = true
                }
            }
        }

        /// Recompute width + inset + redraw after the text or font changed (digit
        /// count or line height may change). No-op in Styled mode.
        func refreshGutter() {
            guard !FormattingPref.isOn, gutter != nil else { return }
            layoutGutter()
        }

        deinit {
            if let formattingObserver { NotificationCenter.default.removeObserver(formattingObserver) }
            if let clipObserver { NotificationCenter.default.removeObserver(clipObserver) }
        }

        func textDidChange(_ notification: Notification) {
            guard !isUpdatingFromBinding,
                  let tv = notification.object as? NSTextView else { return }
            let updated = tv.string
            text = updated
            cachedLineCount = LineNumbering.lineCount(in: updated)
            refreshGutter()
        }

        /// Markdown-aware Return: continue the current list item, or end the
        /// list on an empty item. Returns true when handled (the default
        /// newline is suppressed), false to let a normal newline through.
        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)),
                  let ts = textView.textStorage else { return false }
            let caret = textView.selectedRange()
            guard caret.length == 0 else { return false }

            let nsString = ts.string as NSString
            var lineStart = 0, lineEnd = 0, contentsEnd = 0
            nsString.getLineStart(&lineStart, end: &lineEnd, contentsEnd: &contentsEnd,
                                  for: NSRange(location: caret.location, length: 0))
            // Only act when the caret sits at the end of the line's content.
            guard caret.location == contentsEnd else { return false }

            let line = nsString.substring(with: NSRange(location: lineStart, length: contentsEnd - lineStart))
            switch EditingCommands.listContinuation(forLine: line) {
            case .none:
                return false
            case .continue(let newPrefix):
                let insertion = "\n" + newPrefix
                applyEdit(to: textView, ts: ts, range: caret, replacement: insertion,
                          caretAfter: caret.location + (insertion as NSString).length)
                return true
            case .terminate(let prefixLength):
                applyEdit(to: textView, ts: ts,
                          range: NSRange(location: lineStart, length: prefixLength),
                          replacement: "", caretAfter: lineStart)
                return true
            }
        }

        private func applyEdit(to textView: NSTextView, ts: NSTextStorage,
                               range: NSRange, replacement: String, caretAfter: Int) {
            guard textView.shouldChangeText(in: range, replacementString: replacement) else { return }
            ts.beginEditing()
            ts.replaceCharacters(in: range, with: replacement)
            ts.endEditing()
            textView.didChangeText()
            textView.setSelectedRange(NSRange(location: caretAfter, length: 0))
        }
    }
}

final class ClickableTextView: NSTextView {
    weak var highlighter: MarkdownHighlighter?

    /// The style-adjusted rect of the caret as last drawn. AppKit only
    /// invalidates the thin default caret rect on moves and erases, so the
    /// widened block/underline would otherwise strand stale pixels (ghost
    /// carets); this records exactly what must be repainted.
    private var lastDrawnCaretRect: NSRect?

    /// Draw the caret per `Theme.cursorStyle` by widening / repositioning the
    /// rect and calling super. Block uses reduced alpha so the glyph under it
    /// stays readable. The accent color is supplied by AppKit (set as
    /// `insertionPointColor`). Blink-off is handled by `CaretBlink` (the blink
    /// timer never fires), so an off pass here is always a real erase.
    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        var caretRect = rect
        var caretColor = color
        switch Theme.cursorStyle {
        case .bar:
            break
        case .block:
            caretRect.size.width = CursorGeometry.blockWidth(glyphWidth: glyphWidthAtCaret(),
                                                             fallback: spaceAdvance())
            caretColor = color.withAlphaComponent(0.5)
        case .underline:
            caretRect = CursorGeometry.underlineRect(caret: rect,
                                                     glyphWidth: glyphWidthAtCaret(),
                                                     fallback: spaceAdvance())
        }
        if flag {
            lastDrawnCaretRect = caretRect
        } else if let last = lastDrawnCaretRect,
                  abs(last.origin.x - caretRect.origin.x) < 0.5,
                  abs(last.origin.y - caretRect.origin.y) < 0.5 {
            // Blink hide at the current position: erase exactly what was
            // drawn and schedule NOTHING. An extra invalidation here makes
            // the display pass repaint the caret straight back, which reads
            // as "never blinks" when blink is on.
            caretRect = last
            lastDrawnCaretRect = nil
        } else {
            // Stale erase (the caret moved): AppKit hands back a rect
            // computed from the CURRENT selection, which is the wrong place
            // (and, with a proportional font, the wrong width) for the caret
            // that was actually drawn. Repaint the union so no pixels strand.
            var dirty = caretRect
            if let last = lastDrawnCaretRect { dirty = dirty.union(last) }
            setNeedsDisplay(dirty.insetBy(dx: -2, dy: -2))
            lastDrawnCaretRect = nil
        }
        super.drawInsertionPoint(in: caretRect, color: caretColor, turnedOn: flag)
    }

    /// Clear the previous caret's pixels on every selection change, and widen
    /// the dirty region to the new caret's whole line fragment. AppKit's own
    /// invalidation covers only the thin bar rect, which both strands the old
    /// widened block/underline as a ghost AND clips a display-pass redraw of
    /// the new one to a sliver (bit on vertical moves, where the erase union
    /// sits on another line and cannot cover the new caret's cell).
    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity,
                                    stillSelecting: Bool) {
        if let last = lastDrawnCaretRect {
            setNeedsDisplay(last.insetBy(dx: -2, dy: -2))
            lastDrawnCaretRect = nil
        }
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        invalidateCaretLine()
    }

    /// Make the WHOLE widened caret blink. AppKit's blink machinery never
    /// routes the hide through `drawInsertionPoint`; it just redisplays the
    /// THIN default caret rect, so a block/underline caret only flickered in
    /// its inner strip. When a thin display pass clips the recorded caret
    /// rect, widen the repaint to the full rect: the widened pass then either
    /// hides the whole caret (off phase) or redraws it whole (on phase). The
    /// widened pass is itself wider than the threshold, so this cannot recurse.
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if Theme.cursorBlink, Theme.cursorStyle != .bar,
           let last = lastDrawnCaretRect,
           dirtyRect.width <= 4,
           dirtyRect.intersects(last),
           !dirtyRect.contains(last.insetBy(dx: 1, dy: 1)) {
            // Async, not direct: a direct setNeedsDisplay from inside a draw
            // pass is not flushed until the runloop next spins, which at idle
            // is the NEXT blink tick, so the widened repaint would always land
            // one phase late. The async block wakes the runloop and the
            // repaint commits within the same phase.
            let rect = last.insetBy(dx: -2, dy: -2)
            DispatchQueue.main.async { [weak self] in self?.setNeedsDisplay(rect) }
        }
    }

    /// Mark the caret's whole line fragment as needing display, so a widened
    /// block/underline caret paints in full no matter how thin a rect AppKit
    /// invalidated for the move.
    private func invalidateCaretLine() {
        guard Theme.cursorStyle != .bar, let lm = layoutManager else { return }
        let caret = selectedRange()
        guard caret.length == 0 else { return }
        let length = (string as NSString).length
        var rect: NSRect
        if caret.location >= length {
            rect = lm.extraLineFragmentRect
            if rect.height <= 0, length > 0 {
                let glyph = lm.glyphIndexForCharacter(at: length - 1)
                rect = lm.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            }
        } else {
            let glyph = lm.glyphIndexForCharacter(at: caret.location)
            rect = lm.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        }
        guard rect.height > 0 else { return }
        rect.origin.x += textContainerOrigin.x
        rect.origin.y += textContainerOrigin.y
        setNeedsDisplay(rect.insetBy(dx: -2, dy: -2))
    }

    /// Width of the glyph at the insertion point, or 0 at end-of-line / on a
    /// newline / empty document (caller falls back to a space advance).
    private func glyphWidthAtCaret() -> CGFloat {
        guard let lm = layoutManager, let tc = textContainer, let ts = textStorage else { return 0 }
        let caret = selectedRange().location
        let ns = ts.string as NSString
        guard caret < ns.length, ns.substring(with: NSRange(location: caret, length: 1)) != "\n" else { return 0 }
        let glyphRange = lm.glyphRange(forCharacterRange: NSRange(location: caret, length: 1), actualCharacterRange: nil)
        return lm.boundingRect(forGlyphRange: glyphRange, in: tc).width
    }

    private func spaceAdvance() -> CGFloat {
        (" " as NSString).size(withAttributes: [.font: Theme.editorFont]).width
    }

    /// Force the caret to redraw after a style/blink change. Re-registers the
    /// blink periods first, then restarts the caret timer so it picks them up.
    func refreshCaret() {
        CaretBlink.apply(Theme.cursorBlink)
        needsDisplay = true
        updateInsertionPointStateAndRestartTimer(true)
    }

    static func scrollableClickableTextView() -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = ClickableTextView()
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        return scrollView
    }

    override func mouseDown(with event: NSEvent) {
        guard let highlighter, let ts = textStorage else {
            super.mouseDown(with: event)
            return
        }
        let pointInView = convert(event.locationInWindow, from: nil)
        let pointInContainer = NSPoint(
            x: pointInView.x - textContainerOrigin.x,
            y: pointInView.y - textContainerOrigin.y
        )
        guard let container = textContainer, let layoutManager else {
            super.mouseDown(with: event)
            return
        }
        let glyphIndex = layoutManager.glyphIndex(for: pointInContainer, in: container)
        let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)

        let ranges = highlighter.taskCheckboxRanges(in: ts)
        guard let bracket = ranges.first(where: { NSLocationInRange(charIndex, $0) }) else {
            super.mouseDown(with: event)
            return
        }
        // glyphIndex(for:in:) clamps a click that lands on no glyph to the nearest
        // one, so a click in the line-spacing gap above/below the bracket column
        // would otherwise toggle it. Require the point to fall inside the glyph.
        let glyphRect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyphIndex, length: 1), in: container)
        guard glyphRect.contains(pointInContainer) else {
            super.mouseDown(with: event)
            return
        }
        toggleCheckbox(at: bracket)
    }

    /// Toggles the task checkbox on the line holding the insertion point.
    /// Wired to a Format-menu command so the checkboxes are reachable from the
    /// keyboard and VoiceOver, not just by clicking.
    @objc func toggleTaskCheckbox(_ sender: Any?) {
        guard let highlighter, let ts = textStorage else { return }
        let caret = min(selectedRange().location, ts.length)
        let line = (ts.string as NSString).lineRange(for: NSRange(location: caret, length: 0))
        let ranges = highlighter.taskCheckboxRanges(in: ts)
        guard let bracket = ranges.first(where: { NSLocationInRange($0.location, line) }) else {
            NSSound.beep()
            return
        }
        toggleCheckbox(at: bracket)
    }

    private func toggleCheckbox(at bracket: NSRange) {
        guard let ts = textStorage else { return }
        let innerRange = NSRange(location: bracket.location + 1, length: 1)
        guard NSMaxRange(innerRange) <= ts.length else { return }
        let current = (ts.string as NSString).substring(with: innerRange)
        let replacement = (current == " ") ? "x" : " "

        let priorSelection = selectedRange()
        guard shouldChangeText(in: innerRange, replacementString: replacement) else { return }
        ts.beginEditing()
        ts.replaceCharacters(in: innerRange, with: replacement)
        ts.endEditing()
        didChangeText()
        setSelectedRange(priorSelection)
    }

    /// Wrap or unwrap the selection in a markdown emphasis marker. Bound to the
    /// Format menu's Bold (`**`) and Italic (`*`) commands.
    func macmdBold(_ sender: Any?) { applyEmphasis(marker: "**") }
    func macmdItalic(_ sender: Any?) { applyEmphasis(marker: "*") }
    func macmdStrikethrough(_ sender: Any?) { applyEmphasis(marker: "~~") }
    func macmdCode(_ sender: Any?) { applyEmphasis(marker: "`") }

    private func applyEmphasis(marker: String) {
        guard let ts = textStorage else { return }
        let edit = EditingCommands.emphasisToggle(in: ts.string as NSString,
                                                  selection: selectedRange(),
                                                  marker: marker)
        applyTextEdit(edit)
    }

    /// Wrap the selection as a markdown link `[label](url)`, leaving the `url`
    /// placeholder selected. Bound to the Format menu's Link command.
    func macmdLink(_ sender: Any?) {
        guard let ts = textStorage else { return }
        let edit = EditingCommands.linkWrap(in: ts.string as NSString, selection: selectedRange())
        applyTextEdit(edit)
    }

    /// Apply a computed `EditingCommands.TextEdit` through the undo-aware path.
    private func applyTextEdit(_ edit: EditingCommands.TextEdit) {
        guard let ts = textStorage else { return }
        guard shouldChangeText(in: edit.range, replacementString: edit.replacement) else { return }
        ts.beginEditing()
        ts.replaceCharacters(in: edit.range, with: edit.replacement)
        ts.endEditing()
        didChangeText()
        setSelectedRange(edit.selectionAfter)
    }

    /// Print the document through the standard system print panel. Bound to
    /// File ▸ Print. NSPrintOperation paginates the full (content-sized) view.
    func macmdPrint(_ sender: Any?) {
        NSPrintOperation(view: self).run()
    }
}
