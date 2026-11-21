import AppKit

extension EditorSession {
    /// Starts the drag-out file: flattens the Capture and Fast-encodes it into the private cache
    /// under the Export name. The drag takes the file from the returned handle when the pointer
    /// has moved far enough; nil while the Editor has no Capture.
    func startDragOutFile() -> PendingDragFile? {
        commitTextEditing()
        guard let document else { return nil }
        return PendingDragFile(
            job: document.makeExportJob(level: .fast), snapshot: document.history.state,
            captureNumber: document.captureNumber, captureTime: document.capture.info.captureTime)
    }

    /// The drag-out thumbnail drawn from the document as it is now (nil while the Editor has no
    /// Capture): the Export at thumbnail size, with no full-size image made.
    func makeThumbnail() -> PixelBuffer? {
        guard let document else { return nil }
        return try? ExportThumbnail.render(document.makeExportJob(level: .fast), maxSide: DragOutThumbnail.maxPixelSide)
    }

    /// The drop was taken: the Capture counts as exported as it was when the drag's file was made, so
    /// closing it asks nothing, unless it was edited since. The Editor stays open (only Copy and
    /// Save close it).
    func didDragOut(_ file: PendingDragFile) {
        document?.markExported(file.snapshot)
    }
}
