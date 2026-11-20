import Foundation
import Observation

/// What one Editor edits: a Capture (read-only pixels mapped from its Capture file) and its
/// Annotations, crop and Undo history (`AnnotationHistory`, which is `Codable`). Everything the
/// pipeline needs to Export it is copied into an `ExportJob`.
@MainActor
@Observable
final class EditorDocument {
    /// The number the menu bar app gave this Capture (`open-capture <N>`).
    let captureNumber: Int
    let capture: OpenedCapture
    /// The Annotations, the crop and their Undo and Redo history. Change it only through `edit`.
    /// Not observed: it changes on every pointer move of a drag, and a view that watched it would
    /// be rebuilt each time. What the toolbar needs is `EditorSession.toolbarState`.
    @ObservationIgnored private(set) var history: AnnotationHistory
    /// Runs after every change to `history`, so the canvas can show it.
    @ObservationIgnored var onChange: (() -> Void)?
    /// Runs after every change to `history` and to the exported flag: what the Last Capture's
    /// state file keeps (`LastCapturePersistence`).
    @ObservationIgnored var onPersistableChange: (() -> Void)?
    private(set) var exportedRevision = 0

    /// `exported` says the Capture had no unexported changes when `history` was stored: a Reopen
    /// brings the document back exported (or not) as it was.
    init(
        captureNumber: Int, capture: OpenedCapture, history: AnnotationHistory = AnnotationHistory(),
        exported: Bool = false
    ) {
        self.captureNumber = captureNumber
        self.capture = capture
        self.history = history
        exportedRevision = exported ? history.revision : 0
    }

    /// Bumped by every change the user makes (and every Undo and Redo); Export copies it into
    /// `exportedRevision`.
    var revision: Int { history.revision }
    var annotations: [Annotation] { history.annotations }
    var canUndo: Bool { history.canUndo }
    var canRedo: Bool { history.canRedo }

    /// Changes the history (a gesture's `begin`, `mutate`, `end`; Undo; Redo) and tells the canvas.
    func edit(_ body: (inout AnnotationHistory) -> Void) {
        body(&history)
        onChange?()
        onPersistableChange?()
    }

    /// The Capture's size in points.
    var pointSize: CGSize { capture.info.pointSize }

    /// True when the user changed the document since its last Export.
    var hasUnexportedChanges: Bool { revision != exportedRevision }

    func markExported() {
        exportedRevision = revision
        onPersistableChange?()
    }

    func makeExportJob(level: PNGLevel) -> ExportJob {
        let info = capture.info
        let image = ExportImage(pixels: capture.pixels, scale: info.scale, dpi: info.dpi)
        return ExportJob(
            image: image, level: level, standardResolution: ExportSettings.standardResolution,
            annotations: history.annotations)
    }
}
