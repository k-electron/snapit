import AppKit

extension EditorSession {
    /// Save (the button, ⌘S, the menu): flattens the Capture into a shared memory-mapped export
    /// file and sends the menu bar app a Save request. The menu bar app checks the Save location
    /// is writable straight away and answers; it then Balanced-encodes in the background and writes
    /// `snapit-YYYYMMDD-HHMMSS.png`, so the file still lands when this helper quits straight after
    /// ("Close the Editor after Save"). When the location can't be written to the Editor stays
    /// open and `SaveFailureSignal` tells whoever shows the folder Permission guide.
    func startSave() {
        guard !isExporting, document != nil else { return }
        isExporting = true
        copyTask = Task { await save() }
    }

    private func save() async {
        defer { isExporting = false }
        guard let document else { return }
        let number = document.captureNumber
        var export: SharedExport?
        do {
            let job = document.makeExportJob(level: .balanced)
            let shared = try await ExportPipeline.flattenIntoSharedFile(job, captureTime: document.capture.info.captureTime)
            export = shared
            // A real folder prompt can hold the menu bar app's reply for as long as the user takes.
            let line = try await CommandSocketClient.send(
                .saveExport, arguments: [shared.url.path, shared.downscale ? "1" : "0"],
                to: AppIdentity.appSocketPath, timeoutSeconds: 300)
            switch SaveReply(line: line) {
            case .accepted:
                SaveFailureSignal.record(.handedOver, captureNumber: number, session: self)
                document.markExported()
                if EditorSettings.closeAfterSave { close() }
            case .folderNotWritable(let folder, let code):
                fail(.folderNotWritable(folder: folder, code: code), number: number)
            case .failed(let message):
                fail(.failed(message), number: number)
            }
        } catch {
            if let export { unlink(export.url.path) }
            NSLog("snapit Editor: Save failed: \(error)")
            fail(.failed("\(error)"), number: number)
        }
    }

    private func fail(_ failure: SaveFailure, number: Int) {
        SaveFailureSignal.record(.failed(failure), captureNumber: number, session: self)
        if !SaveFailureSignal.hasObservers && !TestMode.isActive { NSSound.beep() }
    }
}
