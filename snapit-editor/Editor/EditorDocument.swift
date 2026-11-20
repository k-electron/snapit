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
    /// What was last Exported (Copy, Save or a taken drop): the Annotations and crop as they were when
    /// that Export took its snapshot, not as they are by the time it finished. Nil when never Exported.
    private(set) var exportedState: DocumentState?

    /// `exported` says the Capture had no unexported changes when `history` was stored: a Reopen
    /// brings the document back exported (or not) as it was.
    init(
        captureNumber: Int, capture: OpenedCapture, history: AnnotationHistory = AnnotationHistory(),
        exported: Bool = false
    ) {
        self.captureNumber = captureNumber
        self.capture = capture
        self.history = history
        exportedState = exported ? history.state : nil
    }

    /// Bumped by every change the user makes (and every Undo and Redo).
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

    /// True when the document differs from what was last Exported (from the Capture as it was taken,
    /// when nothing was Exported).
    var hasUnexportedChanges: Bool { history.state != (exportedState ?? DocumentState()) }

    /// True when closing this Editor would lose something the user made and never Exported: there
    /// is something to lose (Annotations or a crop) and it differs from what was last Exported.
    /// A Capture left as it was taken, or edited back to what was Exported, loses nothing.
    var hasUnexportedEdits: Bool {
        hasUnexportedChanges && (!annotations.isEmpty || history.state.crop != nil)
    }

    /// An Export finished: `state` is the document as the Export took its snapshot, so an edit made
    /// while the Export ran (a Save waiting on a folder prompt) still counts as unexported.
    func markExported(_ state: DocumentState) {
        exportedState = state
        onPersistableChange?()
    }

    func makeExportJob(level: PNGLevel) -> ExportJob {
        let info = capture.info
        let image = ExportImage(pixels: capture.pixels, scale: info.scale, dpi: info.dpi)
        return ExportJob(
            image: image, level: level, standardResolution: ExportSettings.standardResolution,
            annotations: history.annotations, crop: history.state.crop)
    }
}
