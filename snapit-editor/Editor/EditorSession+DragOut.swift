import AppKit

extension EditorSession {
    /// Starts the drag-out file: flattens the Capture and Fast-encodes it into the private cache
    /// under the Export name. The drag takes the file from the returned handle when the pointer
    /// has moved far enough; nil while the Editor has no Capture.
    func startDragOutFile() -> PendingDragFile? {
        commitTextEditing()
        guard let document else { return nil }
        return PendingDragFile(
            job: document.makeExportJob(level: .fast), captureNumber: document.captureNumber,
            captureTime: document.capture.info.captureTime)
    }

    /// The drop was taken: the Capture counts as exported, so closing it asks nothing. The Editor
    /// stays open (only Copy and Save close it).
    func didDragOut() {
        document?.markExported()
    }
}
