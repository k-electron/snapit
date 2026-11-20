import CoreGraphics

/// The Annotation color, width and text size controls and the eyedropper. They are always there
/// (a toolbar never grows or loses controls by tool); what does not apply to the active tool or
/// the selected Annotation is disabled. With nothing selected they set what the next Annotation
/// gets, so the color controls work as soon as the Editor opens.
extension EditorSession {
    /// The preset swatches, in order.
    static let swatches: [(name: String, color: AnnotationColor)] = [
        ("Red", AnnotationColor(hex: "ff3b30") ?? .red),
        ("Orange", AnnotationColor(hex: "ff9500") ?? .red),
        ("Yellow", AnnotationColor(hex: "ffcc00") ?? .red),
        ("Green", AnnotationColor(hex: "34c759") ?? .red),
        ("Blue", AnnotationColor(hex: "0a84ff") ?? .red),
        ("Purple", AnnotationColor(hex: "af52de") ?? .red),
        ("Black", AnnotationColor(hex: "000000") ?? .red),
        ("White", AnnotationColor(hex: "ffffff") ?? .red),
    ]

    /// The text sizes the size control offers, in points.
    static let textSizes: [CGFloat] = [14, 20, 32]

    // MARK: What the controls show

    /// The color the controls show: the selected Annotation's, else the one the next gets.
    var shownColor: AnnotationColor { toolbarState.selectionColor ?? annotationStyle.color }

    /// The width control in play: the selected Annotation's kind, else the active tool's, else
    /// (Select with nothing selected) the line width the next Arrow, Rectangle or Oval gets.
    var activeWidthChoice: WidthChoice {
        if let choice = toolbarState.selectionWidthChoice { return choice }
        if let kind = currentTool.annotationKind.flatMap(AnnotationKinds.kind) { return kind.widthChoice }
        return .line
    }

    var widthApplies: Bool { activeWidthChoice != .none }

    var shownWidth: CGFloat {
        if let width = toolbarState.selectionWidth, toolbarState.selectionWidthChoice != WidthChoice.none { return width }
        return activeWidthChoice == .highlighter ? highlighterWidth : annotationStyle.width
    }

    /// The size control has three tiles that are text sizes for a Text (selected, being typed or
    /// about to be drawn) and widths for everything else: the two never apply together.
    var sizeControlIsTextSize: Bool {
        if let uses = toolbarState.selectionUsesTextSize { return uses }
        if let kind = currentTool.annotationKind.flatMap(AnnotationKinds.kind) { return kind.usesTextSize }
        return false
    }

    /// Whether the size control does anything now (a kind with no width, Redaction, has none).
    var sizeControlApplies: Bool { sizeControlIsTextSize || widthApplies }

    var shownTextSize: CGFloat { toolbarState.selectionTextSize ?? annotationStyle.textSize }

    // MARK: Eyedropper

    /// The eyedropper button: turns it on, or off.
    func toggleEyedropper() {
        if isEyedropperActive {
            cancelEyedropper()
        } else {
            commitTextEditing()
            isEyedropperActive = true
            refreshCursor()
        }
    }

    @discardableResult
    func cancelEyedropper() -> Bool {
        guard isEyedropperActive else { return false }
        isEyedropperActive = false
        refreshCursor()
        return true
    }

    /// The eyedropper's click: the Capture's pixel under `point` becomes the Annotation color.
    /// A click outside the Capture does nothing.
    func takeColor(at point: CGPoint) {
        guard isEyedropperActive, let document else { return }
        let capture = document.capture
        let pixels = capture.pixels
        guard let pixel = CapturePixelSampler.pixel(containing: point, scale: capture.info.scale, in: pixels),
            let color = CapturePixelSampler.shownColor(
                atX: pixel.x, y: pixel.y, in: pixels, scale: capture.info.scale, window: canvas?.cropPixels,
                redactions: document.annotations.filter { $0.kind == .redaction })
        else { return }
        isEyedropperActive = false
        refreshCursor()
        setAnnotationColor(color)
    }

    private func refreshCursor() {
        canvas.map { $0.window?.invalidateCursorRects(for: $0) }
    }

    // MARK: Color panel

    /// The color wheel button: opens the macOS color panel for this Editor.
    func openColorPanel() {
        ColorPanelController.shared.open(for: self)
    }

    /// Closes the Undo step a color panel drag has open, if one is.
    func endColorGesture() {
        ColorPanelController.shared.endGesture()
    }
}
