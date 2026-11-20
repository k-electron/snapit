import AppKit
import SwiftUI

/// The drag-out thumbnail in the top toolbar: a small preview of the Capture, made by the engine
/// off the main thread. Dragging it out of the Editor offers the Export as a file.
struct DragOutThumbnail: View {
    let session: EditorSession
    @State private var thumbnail: PixelBuffer?

    static let size = CGSize(width: 48, height: 32)
    /// Pixels on the longest side: twice the point size, so it is sharp on Retina.
    nonisolated static let maxPixelSide = 96

    var body: some View {
        DragOutSource(session: session, image: thumbnail?.makeCGImage())
            .frame(width: Self.size.width, height: Self.size.height)
            .help("Drag the Capture out as a file")
            .task(id: session.document?.captureNumber) {
                guard let pixels = session.document?.capture.pixels else { return }
                thumbnail = await Self.makeThumbnail(of: pixels)
            }
    }

    @concurrent
    private static func makeThumbnail(of pixels: PixelBuffer) async -> PixelBuffer? {
        try? pixels.makeThumbnail(maxSide: maxPixelSide)
    }
}

private struct DragOutSource: NSViewRepresentable {
    let session: EditorSession
    let image: CGImage?

    func makeNSView(context: Context) -> DragOutView {
        let view = DragOutView(frame: NSRect(origin: .zero, size: DragOutThumbnail.size))
        view.session = session
        return view
    }

    func updateNSView(_ view: DragOutView, context: Context) {
        view.session = session
        view.image = image
    }
}

/// Starts a file drag once the pointer has moved a few points with the button down. The file
/// is Fast-encoded in the background from the moment the button goes down.
final class DragOutView: NSView, NSDraggingSource {
    weak var session: EditorSession?
    var image: CGImage? {
        didSet { layer?.contents = image }
    }

    private var pending: PendingDragFile?
    private var mouseDownLocation: NSPoint?
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
        pending = session?.startDragOutFile()
    }

    override func mouseDragged(with event: NSEvent) {
        guard !didBeginDrag, let start = mouseDownLocation, let pending else { return }
        let here = convert(event.locationInWindow, from: nil)
        guard hypot(here.x - start.x, here.y - start.y) >= Self.dragThreshold else { return }
        didBeginDrag = true
        let file: URL
        do {
            file = try pending.wait()
        } catch {
            NSLog("snapit Editor: drag-out failed: \(error)")
            NSSound.beep()
            return
        }
        let item = NSDraggingItem(pasteboardWriter: file as NSURL)
        let preview = image.map { NSImage(cgImage: $0, size: bounds.size) } ?? NSWorkspace.shared.icon(forFile: file.path)
        item.setDraggingFrame(bounds, contents: preview)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        mouseDownLocation = nil
        pending = nil
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    func draggingSession(_ draggingSession: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        if operation != [] { session?.didDragOut() }
        pending = nil
    }
}
