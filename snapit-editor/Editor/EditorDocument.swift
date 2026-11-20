import Foundation
import Observation

/// What one Editor edits: a Capture (read-only pixels mapped from its Capture file) and,
/// as tickets add them, its Annotations, crop and Undo history. Everything the pipeline needs
/// to Export it is copied into an `ExportJob`.
@MainActor
@Observable
final class EditorDocument {
    /// The number the menu bar app gave this Capture (`open-capture <N>`).
    let captureNumber: Int
    let capture: OpenedCapture
    /// Bumped by every change the user makes; Export copies it into `exportedRevision`.
    private(set) var revision = 0
    private(set) var exportedRevision = 0

    init(captureNumber: Int, capture: OpenedCapture) {
        self.captureNumber = captureNumber
        self.capture = capture
    }

    /// The Capture's size in points.
    var pointSize: CGSize { capture.info.pointSize }

    /// True when the user changed the document since its last Export.
    var hasUnexportedChanges: Bool { revision != exportedRevision }

    func markExported() { exportedRevision = revision }

    func makeExportJob(level: PNGLevel) -> ExportJob {
        let info = capture.info
        let image = ExportImage(pixels: capture.pixels, scale: info.scale, dpi: info.dpi)
        return ExportJob(image: image, level: level)
    }
}
