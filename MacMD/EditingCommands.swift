import Foundation

/// Pure, UI-free editing logic so the markdown-aware behaviors can be unit
/// tested without a live NSTextView. The view layer applies the results
/// through the undo-aware text-edit path.
enum EditingCommands {

    /// A single replacement to apply to the text storage, plus where the
    /// selection should land afterwards. `range` may extend beyond the caller's
    /// selection (e.g. to swallow flanking markers when unwrapping).
    struct TextEdit: Equatable {
        let range: NSRange
        let replacement: String
        let selectionAfter: NSRange
    }

    enum ListContinuation: Equatable {
        /// Non-empty list item: insert a newline followed by this prefix.
        case `continue`(newPrefix: String)
        /// Empty list item: delete this many UTF-16 units of prefix from the
        /// start of the current line and insert no newline (ends the list).
        case terminate(prefixLength: Int)
        /// Not a list line.
        case none
    }

    /// Wrap the selection in `marker`, or unwrap if the marker already flanks
    /// it. With an empty selection, inserts the empty pair and puts the caret
    /// between the two markers.
    static func emphasisToggle(in text: NSString, selection: NSRange, marker: String) -> TextEdit {
        let markerLength = (marker as NSString).length

        if selection.length == 0 {
            return TextEdit(
                range: selection,
                replacement: marker + marker,
                selectionAfter: NSRange(location: selection.location + markerLength, length: 0)
            )
        }

        let beforeStart = selection.location - markerLength
        let afterStart = selection.location + selection.length
        let markerChar = (marker as NSString).substring(to: 1)

        // A flanking marker only counts for unwrapping when it is exactly the
        // marker AND is not extended by another marker character on its outer
        // side. That stops a lone `*` belonging to a `**` pair from being read
        // as an italic marker, so toggling italic inside **bold** adds italic
        // (wraps to ***word***) instead of stripping a bold asterisk.
        func isExactMarker(markerStart: Int, outerIndex: Int) -> Bool {
            guard markerStart >= 0, markerStart + markerLength <= text.length else { return false }
            guard text.substring(with: NSRange(location: markerStart, length: markerLength)) == marker else { return false }
            if outerIndex < 0 || outerIndex >= text.length { return true }
            return text.substring(with: NSRange(location: outerIndex, length: 1)) != markerChar
        }

        let isFlanked =
            isExactMarker(markerStart: beforeStart, outerIndex: beforeStart - 1) &&
            isExactMarker(markerStart: afterStart, outerIndex: afterStart + markerLength)

        if isFlanked {
            return TextEdit(
                range: NSRange(location: beforeStart, length: selection.length + 2 * markerLength),
                replacement: text.substring(with: selection),
                selectionAfter: NSRange(location: beforeStart, length: selection.length)
            )
        }

        return TextEdit(
            range: selection,
            replacement: marker + text.substring(with: selection) + marker,
            selectionAfter: NSRange(location: selection.location + markerLength, length: selection.length)
        )
    }

    /// Wrap the selection as a markdown link `[label](url)`. With a selection the
    /// selected text becomes the label and the `url` placeholder is returned
    /// selected, so the user can immediately type the destination. With no
    /// selection, inserts `[](url)` with the caret between the brackets to type
    /// the label first.
    static func linkWrap(in text: NSString, selection: NSRange) -> TextEdit {
        let urlPlaceholder = "url"
        if selection.length == 0 {
            return TextEdit(
                range: selection,
                replacement: "[](\(urlPlaceholder))",
                selectionAfter: NSRange(location: selection.location + 1, length: 0)
            )
        }
        let label = text.substring(with: selection)
        let labelLength = (label as NSString).length
        return TextEdit(
            range: selection,
            replacement: "[\(label)](\(urlPlaceholder))",
            // Select the "url" placeholder, which sits just past "[label](".
            selectionAfter: NSRange(location: selection.location + labelLength + 3,
                                    length: (urlPlaceholder as NSString).length)
        )
    }

    /// Decide what Return should do on a list line. Regexes are compiled per
    /// call: Return is human-paced, so the cost is negligible, and a local
    /// `let` keeps this type free of non-Sendable shared state under Swift 6
    /// strict concurrency (so it stays callable off the main actor in tests).
    static func listContinuation(forLine line: String) -> ListContinuation {
        let ns = line as NSString
        let full = NSRange(location: 0, length: ns.length)

        let task = try! NSRegularExpression(pattern: "^([ \\t]*)([-*+])[ \\t]+\\[[ xX]\\]([ \\t]+)(.*)$")
        if let m = task.firstMatch(in: line, range: full) {
            if ns.substring(with: m.range(at: 4)).isEmpty {
                return .terminate(prefixLength: m.range(at: 4).location)
            }
            let indent = ns.substring(with: m.range(at: 1))
            let bullet = ns.substring(with: m.range(at: 2))
            return .continue(newPrefix: "\(indent)\(bullet) [ ] ")
        }

        let unordered = try! NSRegularExpression(pattern: "^([ \\t]*)([-*+])([ \\t]+)(.*)$")
        if let m = unordered.firstMatch(in: line, range: full) {
            if ns.substring(with: m.range(at: 4)).isEmpty {
                return .terminate(prefixLength: m.range(at: 4).location)
            }
            let indent = ns.substring(with: m.range(at: 1))
            let bullet = ns.substring(with: m.range(at: 2))
            return .continue(newPrefix: "\(indent)\(bullet) ")
        }

        let ordered = try! NSRegularExpression(pattern: "^([ \\t]*)([0-9]+)([.)])([ \\t]+)(.*)$")
        if let m = ordered.firstMatch(in: line, range: full) {
            if ns.substring(with: m.range(at: 5)).isEmpty {
                return .terminate(prefixLength: m.range(at: 5).location)
            }
            let indent = ns.substring(with: m.range(at: 1))
            let number = Int(ns.substring(with: m.range(at: 2))) ?? 0
            let delimiter = ns.substring(with: m.range(at: 3))
            return .continue(newPrefix: "\(indent)\(number + 1)\(delimiter) ")
        }

        return .none
    }
}
