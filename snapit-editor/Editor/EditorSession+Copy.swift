import AppKit

extension EditorSession {
    /// Copy (the button, ⌘C, the menu): flattens the Capture through the Export pipeline,
    /// Fast-encodes a PNG, puts it on the pasteboard, then closes the Editor when "Close the
    /// Editor after Copy" is on.
    func startCopy() {
        guard !isExporting, document != nil else { return }
        isExporting = true
        copyTask = Task { await copy() }
    }

    private func copy() async {
        defer { isExporting = false }
        guard let document else { return }
        do {
            let job = document.makeExportJob(level: .fast)
            let png = try await ExportPipeline.runInBackground(job)
            AppPasteboard.write(png, as: .png)
            document.markExported()
            if EditorSettings.closeAfterCopy { close() }
        } catch {
            NSLog("snapit Editor: Copy failed: \(error)")
            NSSound.beep()
        }
    }
}
