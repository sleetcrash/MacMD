import Foundation

/// Two-way scroll-sync channel between one document's editor and its preview,
/// deliberately OUTSIDE SwiftUI: routing per-scroll-tick line updates through
/// @State re-rendered the whole document view on every scrolled line, which is
/// the preview lag reported on Intel hardware. Each side installs its "scroll
/// me" closure; the other side drives it directly.
///
/// Echo suppression: a scroll applied to the follower fires the follower's own
/// scroll observer, which would drive the original side right back (a feedback
/// loop). Whichever side drove a sync most recently stays the driver; the other
/// side's events are ignored until the driver has been quiet for `settle`.
@MainActor
final class ScrollSyncBridge {
    enum Source { case editor, preview }

    /// Installed by the preview coordinator (evaluates scrollToLine JS).
    var scrollPreviewToLine: ((Int) -> Void)?
    /// Installed by the editor coordinator (scrolls the NSScrollView).
    var scrollEditorToLine: ((Int) -> Void)?

    private var lastDrive: (source: Source, at: CFAbsoluteTime)?
    private let settle: CFAbsoluteTime = 0.25
    // Last line each side drove, so the per-tick scroll observers (which fire
    // far more often than the top line changes) cost no WebKit IPC or layout
    // query while the line is unchanged. lastDrive still refreshes on every
    // tick so the driver keeps suppressing echoes while scrolling in place.
    private var lastEditorDriven: Int?
    private var lastPreviewDriven: Int?

    func editorScrolled(toTopLine line: Int) {
        guard allow(.editor) else { return }
        lastDrive = (.editor, CFAbsoluteTimeGetCurrent())
        guard line != lastEditorDriven else { return }
        lastEditorDriven = line
        scrollPreviewToLine?(line)
    }

    func previewScrolled(toTopLine line: Int) {
        guard allow(.preview) else { return }
        lastDrive = (.preview, CFAbsoluteTimeGetCurrent())
        guard line != lastPreviewDriven else { return }
        lastPreviewDriven = line
        scrollEditorToLine?(line)
    }

    private func allow(_ source: Source) -> Bool {
        guard let last = lastDrive, last.source != source else { return true }
        return CFAbsoluteTimeGetCurrent() - last.at > settle
    }
}
