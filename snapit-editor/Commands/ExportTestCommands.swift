import AppKit
import ImageIO
import UniformTypeIdentifiers

nonisolated extension SocketCommand {
    /// `export-name <N>`: the file name Editor N's Export has, from its Capture's time
    /// (`snapit-YYYYMMDD-HHMMSS.png`). Test mode only.
    static let exportName = SocketCommand("export-name")
    /// `editor-save-outcome <N>`: how the latest Save of Editor N ended: `none`, `handed-over`
    /// (the menu bar app has the image and writes the file) or `failed folder-not-writable <errno>
    /// <folder>` / `failed <message>`. Test mode only.
    static let editorSaveOutcome = SocketCommand("editor-save-outcome")
    /// `editor-drag-file <N>`: does what pressing the mouse on Editor N's thumbnail does (Fast-encodes
    /// the Export into the private cache), waits for the file and replies `ok <path>`. Test mode only.
    static let editorDragFile = SocketCommand("editor-drag-file")
    /// `editor-drag-thumbnail <N>`: the drag-out thumbnail view of Editor N: `view=<w>x<h> thumbnail=<w>x<h>|none`
    /// (point size of the view, pixel size of its image). Test mode only.
    static let editorDragThumbnail = SocketCommand("editor-drag-thumbnail")
    /// `editor-drag-image <N>`: presses the thumbnail of Editor N (what the mouse going down does), writes the
    /// image the drag would show to the run's `probe` folder as a PNG and replies `ok <path>`; the press is then
    /// let go. Test mode only.
    static let editorDragImage = SocketCommand("editor-drag-image")
}

extension SocketCommandRegistry {
    /// Test-mode commands for Save and drag-out.
    func registerExportTestCommands() {
        guard TestMode.isActive else { return }

        register(.exportName) { request in
            guard let document = Self.exportSession(request)?.document else { return "error export-name <N>" }
            return ExportFileName.fileName(captureTime: document.capture.info.captureTime)
        }
        register(.editorSaveOutcome) { request in
            guard let number = request.arguments.first.flatMap(Int.init) else { return "error editor-save-outcome <N>" }
            switch SaveFailureSignal.outcome(captureNumber: number) {
            case nil: return "none"
            case .handedOver?: return "handed-over"
            case .failed(.folderNotWritable(let folder, let code))?: return "failed folder-not-writable \(code) \(folder)"
            case .failed(.failed(let message))?: return "failed \(message)"
            }
        }
        register(.editorDragFile) { request in
            guard let pending = Self.exportSession(request)?.startDragOutFile() else { return "error editor-drag-file <N>" }
            let outcome = await Task.detached { Result { try pending.wait() } }.value
            switch outcome {
            case .success(let url): return "ok \(url.path)"
            case .failure(let error): return "error \(error)"
            }
        }
        register(.editorDragThumbnail) { request in
            guard let content = Self.exportSession(request)?.window?.contentView,
                let view = Self.find(DragOutView.self, in: content)
            else { return "error no drag-out thumbnail" }
            let size = view.image.map { "\($0.width)x\($0.height)" } ?? "none"
            return "view=\(Int(view.bounds.width))x\(Int(view.bounds.height)) thumbnail=\(size)"
        }
        register(.editorDragImage) { request in
            guard let content = Self.exportSession(request)?.window?.contentView,
                let view = Self.find(DragOutView.self, in: content), let folder = TestMode.folder("probe")
            else { return "error editor-drag-image <N>" }
            view.press()
            defer { view.finishDrag(operation: []) }
            let url = folder.appendingPathComponent("drag-image.png")
            guard let image = view.dragImage, Self.writePNG(image, to: url) else { return "error no drag image" }
            return "ok \(url.path)"
        }
    }

    private static func writePNG(_ image: CGImage, to url: URL) -> Bool {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { return false }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination)
    }

    private static func exportSession(_ request: SocketRequest) -> EditorSession? {
        request.arguments.first.flatMap(Int.init).flatMap { EditorSessions.shared.session(captureNumber: $0) }
    }

    private static func find<V: NSView>(_ type: V.Type, in view: NSView) -> V? {
        if let match = view as? V { return match }
        for child in view.subviews {
            if let match = find(type, in: child) { return match }
        }
        return nil
    }
}
