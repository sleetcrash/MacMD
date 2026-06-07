import SwiftUI
import AppKit

struct MarkdownTextView: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat
    var fontFamily: FontFamily
    var coloring: Coloring
    var palette: Palette?
    var appearance: AppAppearance
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
        scrollView.backgroundColor = .textBackgroundColor

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
        textView.backgroundColor = .textBackgroundColor
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
        context.coordinator.loadInitial(text: text)
        context.coordinator.observeFormatting(textView: textView)
        context.coordinator.syncGutter()

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

        static let baseInsetWidth: CGFloat = 24
        static let insetHeight: CGFloat = 20

        init(text: Binding<String>) {
            self._text = text
        }

        func loadInitial(text: String) {
            guard !hasLoaded, let tv = textView, let ts = tv.textStorage else { return }
            hasLoaded = true
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
            text = tv.string
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

    /// Draw the caret per `Theme.cursorStyle` by widening / repositioning the
    /// rect and calling super (which handles both the draw and the erase pass for
    /// the same rect). Block uses reduced alpha so the glyph under it stays
    /// readable. The accent color is supplied by AppKit (set as
    /// `insertionPointColor`).
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
            let thickness: CGFloat = 2
            caretRect.origin.y = rect.maxY - thickness
            caretRect.size.height = thickness
        }
        // Blink off: force the caret drawn even on the timer's "off" pass.
        let on = Theme.cursorBlink ? flag : true
        super.drawInsertionPoint(in: caretRect, color: caretColor, turnedOn: on)
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

    /// Force the caret to redraw after a style/blink change.
    func refreshCaret() {
        needsDisplay = true
        updateInsertionPointStateAndRestartTimer(true)
    }

    /// Blink off: keep the caret steady by not letting the blink timer toggle it
    /// off. Combined with `drawInsertionPoint` forcing `on = true` when blink is
    /// off, the caret stays visible. HONEST NOTE: NSTextView caret blinking is
    /// fiddly; if live verification shows residual blink or artifacts, ship
    /// Bar/Block/Underline without blink-off and add a FUTURE.md row.
    override func updateInsertionPointStateAndRestartTimer(_ restartFlag: Bool) {
        super.updateInsertionPointStateAndRestartTimer(Theme.cursorBlink ? restartFlag : false)
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
