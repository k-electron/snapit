import AppKit
import SwiftUI

/// The drag-out thumbnail in the top toolbar: a small preview of the Capture as it will be
/// Exported (crop and Annotations included), made by the engine off the main thread. Dragging it
/// out of the Editor offers the Export as a file.
struct DragOutThumbnail: View {
    let session: EditorSession
    @State private var image: CGImage?

    static let size = CGSize(width: 48, height: 32)
    static let tooltip = "Drag the Capture out as a file"
    /// Pixels on the longest side: twice the point size, so it is sharp on Retina.
    nonisolated static let maxPixelSide = 96
    /// After an edit the thumbnail waits this long for the next one before it is made again (a
    /// one-shot wait that the next edit cancels, never a timer).
    private static let settleTime = Duration.milliseconds(400)

    /// What the thumbnail is made from: it is made again when either changes.
    private struct Source: Equatable {
        let captureNumber: Int?
        let revision: Int
    }

    var body: some View {
        DragOutSource(session: session, image: image)
            .frame(width: Self.size.width, height: Self.size.height)
            .help(Self.tooltip)
            .task(id: Source(captureNumber: session.document?.captureNumber, revision: session.toolbarState.revision)) {
                guard let document = session.document else { return }
                if image != nil { try? await Task.sleep(for: Self.settleTime) }
                guard !Task.isCancelled else { return }
                let job = document.makeExportJob(level: .fast)
                let thumbnail = await Self.makeThumbnail(of: job)
                guard !Task.isCancelled else { return }
                image = thumbnail?.makeCGImage()
            }
    }

    @concurrent
    private static func makeThumbnail(of job: ExportJob) async -> PixelBuffer? {
        guard let flattened = try? ExportPipeline.flatten(job) else { return nil }
        return try? flattened.pixels.makeThumbnail(maxSide: maxPixelSide)
    }
}

private struct DragOutSource: NSViewRepresentable {
    let session: EditorSession
    let image: CGImage?

    func makeNSView(context: Context) -> DragOutView {
        let view = DragOutView(frame: NSRect(origin: .zero, size: DragOutThumbnail.size))
        view.session = session
        view.toolTip = DragOutThumbnail.tooltip
        return view
    }

    func updateNSView(_ view: DragOutView, context: Context) {
        view.session = session
        if view.image !== image { view.image = image }
    }
}

/// Starts a file drag once the pointer has moved a few points with the button down. The file
/// is Fast-encoded in the background from the moment the button goes down; if it is not ready
/// when the pointer has moved far enough, the drag starts as soon as it is (the main thread never
/// waits).
final class DragOutView: NSView, NSDraggingSource {
    weak var session: EditorSession?
    var image: CGImage? {
        didSet { layer?.contents = image }
    }

    private var pending: PendingDragFile?
    private var mouseDownLocation: NSPoint?
    private var lastDragEvent: NSEvent?
    private var wantsDrag = false
    private var didBeginDrag = false

    /// How far the pointer moves before the drag starts, in points.
    static let dragThreshold: CGFloat = 3

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.contentsGravity = .resizeAspect
        layer?.magnificationFilter = .linear
        layer?.minificationFilter = .trilinear
        layer?.cornerRadius = 6
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateLayer() {
        layer?.borderColor = NSColor.separatorColor.cgColor
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownLocation = convert(event.locationInWindow, from: nil)
        didBeginDrag = false
        wantsDrag = false
        lastDragEvent = nil
        pending = session?.startDragOutFile()
        pending?.notify { [weak self] _ in
            DispatchQueue.main.async { self?.beginDragIfReady() }
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard !didBeginDrag, let start = mouseDownLocation else { return }
        lastDragEvent = event
        let here = convert(event.locationInWindow, from: nil)
        if hypot(here.x - start.x, here.y - start.y) >= Self.dragThreshold { wantsDrag = true }
        beginDragIfReady()
    }

    override func mouseUp(with event: NSEvent) {
        mouseDownLocation = nil
        wantsDrag = false
        lastDragEvent = nil
        pending = nil
    }

    /// Starts the drag session once the pointer has moved far enough and the file is encoded.
    private func beginDragIfReady() {
        guard wantsDrag, !didBeginDrag, let pending, let event = lastDragEvent else { return }
        guard let outcome = pending.outcome else { return }  // still encoding: `mouseDown`'s notify calls back
        didBeginDrag = true
        switch outcome {
        case .failure(let error):
            NSLog("snapit Editor: drag-out failed: \(error)")
            NSSound.beep()
        case .success(let file):
            let item = NSDraggingItem(pasteboardWriter: file as NSURL)
            let preview = image.map { NSImage(cgImage: $0, size: bounds.size) } ?? NSWorkspace.shared.icon(forFile: file.path)
            item.setDraggingFrame(bounds, contents: preview)
            beginDraggingSession(with: [item], event: event, source: self)
        }
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    func draggingSession(_ draggingSession: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        if operation != [] { session?.didDragOut() }
        pending = nil
    }
}
