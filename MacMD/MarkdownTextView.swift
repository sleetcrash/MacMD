import SwiftUI
import AppKit

struct MarkdownTextView: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor

        guard let textView = scrollView.documentView as? NSTextView else {
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

        textView.delegate = context.coordinator
        textView.textStorage?.delegate = context.coordinator.highlighter

        context.coordinator.textView = textView
        context.coordinator.loadInitial(text: text)

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        let currentNS = textView.string as NSString
        let targetNS = text as NSString
        if currentNS.length != targetNS.length || currentNS as String != text {
            context.coordinator.replace(textView: textView, with: text)
        }
    }

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
            highlighter.rehighlightAll(ts)
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
            let clampedLocation = min(oldSelection.location, newLength)
            let clampedLength = min(oldSelection.length, newLength - clampedLocation)
            textView.setSelectedRange(NSRange(location: clampedLocation, length: clampedLength))
            isUpdatingFromBinding = false
        }

        func textDidChange(_ notification: Notification) {
            guard !isUpdatingFromBinding,
                  let tv = notification.object as? NSTextView else { return }
            text = tv.string
        }
    }
}
