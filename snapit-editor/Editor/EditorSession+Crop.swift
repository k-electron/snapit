import CoreGraphics

/// What the Crop tool is doing between a press and the release.
enum CropDrag {
    /// Dragging out a new rectangle from `anchor`.
    case drawing(anchor: CGPoint)
    /// Dragging the whole rectangle; `original` is how it was when the press began.
    case moving(original: CGRect, from: CGPoint)
    /// Dragging one handle of `original`.
    case resizing(original: CGRect, handle: CropHandle)
}

/// The Crop tool's state on a session: the rectangle being worked on, in image points, which is
/// not part of the document until it is applied (`rect` is the crop to be, or nil while the tool
/// is not active), and the drag in progress.
struct CropState {
    var rect: CGRect?
    var drag: CropDrag?
    /// The rectangle before a drag that draws a new one, restored when the drag is too small.
    var beforeDrawing: CGRect?
}

/// Crop: the Crop tool's actions. The tool's pointer hooks, the Apply Crop button and Enter, the
/// Cancel button and Esc all call these, so each exists once. Applying one is a single change to
/// `DocumentState.crop`, so Undo takes it back; everything the Export needs from it is that
/// rectangle (`CropStage`).
extension EditorSession {
    var isCropping: Bool { selectedToolID == CropTool.toolID }

    private var imageBounds: CGRect { CGRect(origin: .zero, size: document?.pointSize ?? .zero) }

    /// How near the pointer must be to a handle to grab it, in view points.
    private static let handleReach: CGFloat = 10

    /// Called when the active tool changes: choosing Crop starts from the applied crop (or the
    /// whole Capture) with nothing selected; leaving it drops what was not applied.
    func cropToolChanged(from old: String, to new: String) {
        if new == CropTool.toolID, old != new {
            selectAnnotation(nil)
            cropState = CropState(rect: document?.crop ?? imageBounds)
        } else if old == CropTool.toolID, old != new {
            cropState = CropState()
        }
        syncCropView()
    }

    /// Shows the crop on the canvas: while the Crop tool is active the whole Capture with the
    /// rectangle being worked on, otherwise only what the applied crop keeps. Runs after every
    /// change to the document, so Undo and Redo of a crop show at once.
    func syncCropView() {
        guard let canvas, let document else { return }
        if isCropping {
            if cropState.rect == nil { cropState.rect = document.crop ?? imageBounds }
            canvas.setCrop(nil)
            canvas.showCropDraft(cropState.rect)
        } else {
            canvas.showCropDraft(nil)
            canvas.setCrop(document.cropPixels)
        }
    }

    // MARK: Pointer

    func beginCropDrag(at point: CGPoint) {
        guard isCropping, document != nil, cropState.drag == nil, let rect = cropState.rect else { return }
        let reach = Self.handleReach / (canvas?.zoom ?? 1)
        if let handle = CropGeometry.handle(at: point, in: rect, reach: reach) {
            cropState.drag = .resizing(original: rect, handle: handle)
        } else if rect.contains(point) {
            cropState.drag = .moving(original: rect, from: point)
        } else {
            cropState.beforeDrawing = rect
            cropState.drag = .drawing(anchor: point)
        }
    }

    func continueCropDrag(to point: CGPoint) {
        guard let drag = cropState.drag else { return }
        let bounds = imageBounds
        switch drag {
        case .drawing(let anchor):
            cropState.rect = CropGeometry.spanned(from: anchor, to: point, in: bounds)
        case .moving(let original, let from):
            let delta = CGSize(width: point.x - from.x, height: point.y - from.y)
            cropState.rect = CropGeometry.moved(original, by: delta, in: bounds)
        case .resizing(let original, let handle):
            cropState.rect = CropGeometry.resized(original, handle: handle, to: point, in: bounds)
        }
        canvas?.showCropDraft(cropState.rect)
    }

    /// The release: a new rectangle too small to be a crop (a click) puts the old one back.
    func finishCropDrag(at point: CGPoint) {
        continueCropDrag(to: point)
        if case .drawing = cropState.drag, let rect = cropState.rect,
            rect.width < CropGeometry.minimumSize || rect.height < CropGeometry.minimumSize
        {
            cropState.rect = cropState.beforeDrawing
            canvas?.showCropDraft(cropState.rect)
        }
        cropState.drag = nil
        cropState.beforeDrawing = nil
    }

    // MARK: Apply and cancel

    /// Apply Crop (the button, Enter): the rectangle becomes the document's crop, snapped to
    /// device pixels, as one Undo step; a rectangle that keeps the whole Capture removes the crop.
    /// The Editor goes back to Select, showing only what the crop keeps.
    func applyCrop() {
        guard isCropping, let document, let rect = cropState.rect else { return }
        let info = document.capture.info
        var applied: CGRect?
        if let area = CropGeometry.pixelRect(rect, scale: info.scale, width: info.width, height: info.height),
            area != PixelRect(x: 0, y: 0, width: info.width, height: info.height)
        {
            applied = CropGeometry.points(area, scale: info.scale)
        }
        if applied != document.crop {
            document.edit { $0.change { $0.crop = applied } }
        }
        selectTool(id: ToolRegistry.initial.id)
    }

    /// Cancel Crop (the button, Esc): leaves the Crop tool and drops the rectangle.
    func cancelCrop() {
        guard isCropping else { return }
        selectTool(id: ToolRegistry.initial.id)
    }

    /// Esc while cropping cancels the crop instead of closing the Editor; true when it did.
    func cancelCropIfCropping() -> Bool {
        guard isCropping else { return false }
        cancelCrop()
        return true
    }
}
