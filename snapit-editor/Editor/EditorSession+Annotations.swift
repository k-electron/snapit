import CoreGraphics

/// What the pointer is doing to the Annotations between its press and release. One Undo step
/// comes out of each (the document brackets it with `begin` and `end`).
enum AnnotationGesture {
    /// Dragging out a new Annotation; `previousSelection` is what was selected before.
    case drawing(id: Int, previousSelection: Int?)
    /// Dragging an Annotation; `original` is how it was when the press began.
    case moving(original: Annotation, from: CGPoint)
    /// Dragging one of the selected Annotation's handles, grabbed `grab` away from its centre.
    case resizing(original: Annotation, handle: Int, grab: CGSize)
}

/// The Annotation actions: drawing, selecting, moving, resizing, deleting, Undo, Redo and the
/// style. A tool's pointer hooks, a toolbar item's `perform` and a test command all call these,
/// so each exists once. The state lives on the session (one per open Editor), never on a tool:
/// tools are shared by every Editor.
extension EditorSession {
    /// A drag shorter than this (in image points) draws nothing.
    private static let smallestDrawing: CGFloat = 3
    /// How near the pointer must be to a handle or a thin line to grab it, in view points.
    private static let grabDistance: CGFloat = 8

    var annotations: [Annotation] { document?.annotations ?? [] }
    var selectedAnnotation: Annotation? { selectedAnnotationID.flatMap { document?.history.annotation(id: $0) } }
    private var zoom: CGFloat { canvas?.zoom ?? 1 }

    /// Shows the document's Annotations on the canvas. Runs after every change to them. The
    /// selection never outlives its Annotation (Undo can remove it).
    func annotationsDidChange() {
        guard let document else { return }
        if let id = selectedAnnotationID, document.history.annotation(id: id) == nil { selectedAnnotationID = nil }
        canvas?.showAnnotations(document.annotations, selected: selectedAnnotation)
    }

    func selectAnnotation(_ id: Int?) {
        selectedAnnotationID = id
        annotationsDidChange()
    }

    // MARK: Drawing

    /// Starts a new Annotation of this kind at `point`, in the style used last.
    func beginDrawing(_ kindID: AnnotationKindID, at point: CGPoint) {
        guard let document, annotationGesture == nil, let kind = AnnotationKinds.kind(kindID) else { return }
        var style = annotationStyle
        style.filled = style.filled && kind.supportsFill
        var id = 0
        document.edit { history in
            history.begin()
            id = history.makeID()
            history.mutate {
                $0.annotations.append(Annotation(id: id, kind: kindID, start: point, end: point, style: style))
            }
        }
        annotationGesture = .drawing(id: id, previousSelection: selectedAnnotationID)
        selectAnnotation(id)
    }

    func continueDrawing(to point: CGPoint) {
        guard case .drawing(let id, _) = annotationGesture, var annotation = document?.history.annotation(id: id)
        else { return }
        annotation.end = point
        replace(annotation)
    }

    /// Finishes the drawing: one Undo step, or nothing when the drag was too short to be one.
    func finishDrawing(at point: CGPoint) {
        guard case .drawing(let id, let previous) = annotationGesture, var annotation = document?.history.annotation(id: id)
        else { return }
        annotation.end = point
        replace(annotation)
        if hypot(annotation.end.x - annotation.start.x, annotation.end.y - annotation.start.y) < Self.smallestDrawing {
            document?.edit { $0.abort() }
            annotationGesture = nil
            selectAnnotation(previous)
        } else {
            endAnnotationGesture()
        }
    }

    // MARK: Select

    /// The topmost Annotation under `point`, by its exact shape.
    func annotation(at point: CGPoint) -> Annotation? {
        let width = Self.grabDistance / zoom
        return annotations.last { annotation in
            AnnotationKinds.kind(annotation.kind)?.hit(annotation, at: point, minimumWidth: width) == true
        }
    }

    private func handleIndex(of annotation: Annotation, at point: CGPoint) -> Int? {
        guard let kind = AnnotationKinds.kind(annotation.kind) else { return nil }
        let reach = Self.grabDistance / zoom
        return kind.handles(of: annotation).firstIndex { hypot($0.x - point.x, $0.y - point.y) <= reach }
    }

    /// Select's press: a handle of the selected Annotation starts a resize, an Annotation
    /// starts a move (and becomes selected), empty canvas deselects.
    func beginSelecting(at point: CGPoint) {
        guard document != nil, annotationGesture == nil else { return }
        if let selected = selectedAnnotation, let handle = handleIndex(of: selected, at: point),
            let center = AnnotationKinds.kind(selected.kind)?.handles(of: selected)[handle]
        {
            document?.edit { $0.begin() }
            annotationGesture = .resizing(
                original: selected, handle: handle, grab: CGSize(width: point.x - center.x, height: point.y - center.y))
        } else if let hit = annotation(at: point) {
            selectAnnotation(hit.id)
            document?.edit { $0.begin() }
            annotationGesture = .moving(original: hit, from: point)
        } else {
            selectAnnotation(nil)
        }
    }

    func continueSelecting(to point: CGPoint) {
        switch annotationGesture {
        case .moving(let original, let from):
            replace(original.moved(by: CGSize(width: point.x - from.x, height: point.y - from.y)))
        case .resizing(let original, let handle, let grab):
            guard let kind = AnnotationKinds.kind(original.kind) else { return }
            replace(kind.moveHandle(handle, to: CGPoint(x: point.x - grab.width, y: point.y - grab.height), in: original))
        default:
            break
        }
    }

    /// Select's release: one Undo step when the Annotation really moved, nothing for a click.
    func finishSelecting() {
        switch annotationGesture {
        case .moving, .resizing: endAnnotationGesture()
        default: break
        }
    }

    // MARK: Gesture bookkeeping

    private func endAnnotationGesture() {
        document?.edit { $0.end() }
        annotationGesture = nil
    }

    /// Puts everything back as it was before the pointer was pressed (the tool changed, or the
    /// window is closing).
    func abortAnnotationGesture() {
        guard let gesture = annotationGesture else { return }
        document?.edit { $0.abort() }
        annotationGesture = nil
        if case .drawing(_, let previous) = gesture { selectAnnotation(previous) }
    }

    private func replace(_ annotation: Annotation) {
        document?.edit { history in
            history.mutate { state in
                if let index = state.annotations.firstIndex(where: { $0.id == annotation.id }) {
                    state.annotations[index] = annotation
                }
            }
        }
    }

    // MARK: Delete, Undo, Redo

    var canDeleteAnnotation: Bool { selectedAnnotation != nil && annotationGesture == nil }

    /// Delete Annotation (⌫): removes the selected Annotation.
    func deleteSelectedAnnotation() {
        guard canDeleteAnnotation, let id = selectedAnnotationID else { return }
        document?.edit { history in
            history.change { $0.annotations.removeAll { $0.id == id } }
        }
    }

    var canUndo: Bool { document?.canUndo == true && annotationGesture == nil }
    var canRedo: Bool { document?.canRedo == true && annotationGesture == nil }

    func undo() {
        guard canUndo else { return }
        document?.edit { $0.undo() }
    }

    func redo() {
        guard canRedo else { return }
        document?.edit { $0.redo() }
    }

    // MARK: Style

    /// True when the outline / solid fill choice does something now: the selected Annotation, or
    /// the active tool's, is a Rectangle or an Oval.
    var fillApplies: Bool {
        if let selected = selectedAnnotation { return AnnotationKinds.kind(selected.kind)?.supportsFill == true }
        return currentTool.annotationKind.flatMap(AnnotationKinds.kind)?.supportsFill == true
    }

    /// Whether the fill the user sees chosen is solid: the selected Annotation's, else the one
    /// new Annotations get.
    var fillIsSolid: Bool {
        if let selected = selectedAnnotation, AnnotationKinds.kind(selected.kind)?.supportsFill == true {
            return selected.style.filled
        }
        return annotationStyle.filled
    }

    /// Outline or solid fill: for the selected Rectangle or Oval, and for the next ones.
    func setAnnotationFilled(_ filled: Bool) {
        annotationStyle.filled = filled
        AnnotationSettings.filled = filled
        restyleSelection(onlyIfFillable: true) { $0.filled = filled }
    }

    /// The line width in points, for the selected Annotation and for the next ones.
    func setAnnotationWidth(_ width: CGFloat) {
        annotationStyle.width = width
        AnnotationSettings.width = width
        restyleSelection { $0.width = width }
    }

    /// The Annotation color, for the selected Annotation and for the next ones.
    func setAnnotationColor(_ color: AnnotationColor) {
        annotationStyle.color = color
        AnnotationSettings.color = color
        restyleSelection { $0.color = color }
    }

    /// Changes the selected Annotation's style as one Undo step.
    private func restyleSelection(onlyIfFillable: Bool = false, _ change: (inout AnnotationStyle) -> Void) {
        guard annotationGesture == nil, let selected = selectedAnnotation,
            let kind = AnnotationKinds.kind(selected.kind), !onlyIfFillable || kind.supportsFill
        else { return }
        var updated = selected
        change(&updated.style)
        guard updated != selected else { return }
        document?.edit { history in
            history.change { state in
                if let index = state.annotations.firstIndex(where: { $0.id == updated.id }) {
                    state.annotations[index] = updated
                }
            }
        }
    }
}
