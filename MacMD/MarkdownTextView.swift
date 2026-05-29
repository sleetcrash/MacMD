import SwiftUI
import AppKit

struct MarkdownTextView: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        Theme.setEditorFontSize(fontSize)
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
        context.coordinator.loadInitial(text: text)

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        if Theme.setEditorFontSize(fontSize) {
            context.coordinator.applyFontChange(to: textView)
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
            if text.utf8.count >= MarkdownDocument.softSizeLimit {
                highlighter.isDisabled = true
            } else {
                highlighter.rehighlightAll(ts)
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
        }

        func textDidChange(_ notification: Notification) {
            guard !isUpdatingFromBinding,
                  let tv = notification.object as? NSTextView else { return }
            text = tv.string
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

    private func applyEmphasis(marker: String) {
        guard let ts = textStorage else { return }
        let edit = EditingCommands.emphasisToggle(in: ts.string as NSString,
                                                  selection: selectedRange(),
                                                  marker: marker)
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
