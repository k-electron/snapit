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

/// What the toolbar needs to know about the Annotations (see `EditorSession.toolbarState`).
struct AnnotationToolbarState: Equatable {
    var canUndo = false
    var canRedo = false
    var canDelete = false
    /// Whether the selected Annotation comes as an outline or a solid fill; nil with no selection.
    var selectionSupportsFill: Bool?
    /// The selected Annotation's fill is solid.
    var selectionFilled = false
    /// The selected Annotation's color, width and text size, and which controls apply to its
    /// kind; nil with no selection. The color, width and size controls show these.
    var selectionColor: AnnotationColor?
    var selectionWidth: CGFloat?
    var selectionWidthChoice: WidthChoice?
    var selectionTextSize: CGFloat?
    var selectionUsesTextSize: Bool?
    /// The document's revision after the last finished change: what the drag-out thumbnail is
    /// made again for. It does not move while a gesture is in progress.
    var revision = 0
}

/// The Annotation actions: drawing, selecting, moving, resizing, deleting, Undo, Redo and the
/// style. A tool's pointer hooks, a toolbar item's `perform` and a test command all call these,
/// so each exists once. The state lives on the session (one per open Editor), never on a tool:
/// tools are shared by every Editor.
extension EditorSession {
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
        refreshToolbarState()
    }

    func selectAnnotation(_ id: Int?) {
        selectedAnnotationID = id
        annotationsDidChange()
    }

    /// Recomputes `toolbarState`, and only stores it when it is different.
    func refreshToolbarState() {
        var state = AnnotationToolbarState()
        let idle = annotationGesture == nil
        state.revision = idle ? (document?.revision ?? 0) : toolbarState.revision
        state.canUndo = idle && document?.canUndo == true
        state.canRedo = idle && document?.canRedo == true
        if let selected = selectedAnnotation {
            state.canDelete = idle
            state.selectionSupportsFill = AnnotationKinds.kind(selected.kind)?.supportsFill ?? false
            state.selectionFilled = selected.style.filled
            state.selectionColor = selected.style.color
            state.selectionWidth = selected.style.width
            state.selectionWidthChoice = AnnotationKinds.kind(selected.kind)?.widthChoice ?? WidthChoice.none
            state.selectionTextSize = selected.style.textSize
            state.selectionUsesTextSize = AnnotationKinds.kind(selected.kind)?.usesTextSize ?? false
        }
        if state != toolbarState { toolbarState = state }
    }

    // MARK: Drawing

    /// Starts a new Annotation of this kind at `point`, in the style used last.
    func beginDrawing(_ kindID: AnnotationKindID, at point: CGPoint) {
        guard let document, annotationGesture == nil, let kind = AnnotationKinds.kind(kindID) else { return }
        endColorGesture()
        var style = annotationStyle
        style.filled = style.filled && kind.supportsFill
        if kind.widthChoice == .highlighter { style.width = highlighterWidth }
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

    /// Finishes the drawing: one Undo step, or nothing when the drag was too short to leave
    /// something to see and click.
    func finishDrawing(at point: CGPoint) {
        guard case .drawing(let id, let previous) = annotationGesture, var annotation = document?.history.annotation(id: id)
        else { return }
        annotation.end = point
        replace(annotation)
        if AnnotationKinds.kind(annotation.kind)?.isLargeEnough(annotation) == true {
            endAnnotationGesture()
        } else {
            document?.edit { $0.abort() }
            annotationGesture = nil
            selectAnnotation(previous)
        }
    }

    // MARK: Select

    /// The topmost Annotation under `point`, by its exact shape. Topmost is the order Export
    /// paints in (Redactions beneath all the others).
    func annotation(at point: CGPoint) -> Annotation? {
        let width = Self.grabDistance / zoom
        return AnnotationKinds.paintOrder(annotations).last { annotation in
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
        endColorGesture()
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

    /// Select's release: one Undo step when the Annotation really moved or was resized, nothing
    /// for a click, and no change at all when a resize left it too small to see.
    func finishSelecting() {
        switch annotationGesture {
        case .moving:
            endAnnotationGesture()
        case .resizing(let original, _, _):
            if let current = document?.history.annotation(id: original.id),
                AnnotationKinds.kind(current.kind)?.isLargeEnough(current) == true
            {
                endAnnotationGesture()
            } else {
                abortAnnotationGesture()
            }
        default:
            break
        }
    }

    // MARK: Gesture bookkeeping

    private func endAnnotationGesture() {
        document?.edit { $0.end() }
        annotationGesture = nil
    }

    /// Puts everything back as it was before the pointer was pressed (the tool changed, the
    /// resize went too small, or the window is closing).
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

    var canDeleteAnnotation: Bool { toolbarState.canDelete }
    /// While a text is being typed, Undo takes back its typing first.
    var canUndo: Bool {
        _ = textEditRevision
        return toolbarState.canUndo || textEditingCanUndo
    }

    var canRedo: Bool {
        _ = textEditRevision
        return toolbarState.canRedo || textEditingCanRedo
    }

    /// Delete Annotation (⌫): removes the selected Annotation.
    func deleteSelectedAnnotation() {
        guard annotationGesture == nil, let id = selectedAnnotationID else { return }
        document?.edit { history in
            history.change { $0.annotations.removeAll { $0.id == id } }
        }
    }

    /// Undo (⌘Z): the typing of a text being edited first, then the Annotations.
    func undo() {
        if undoTextEditing() { return }
        endColorGesture()
        guard annotationGesture == nil, document?.canUndo == true else { return }
        document?.edit { $0.undo() }
    }

    func redo() {
        if redoTextEditing() { return }
        endColorGesture()
        guard annotationGesture == nil, document?.canRedo == true else { return }
        document?.edit { $0.redo() }
    }

    // MARK: Style

    /// True when the outline / solid fill choice does something now: the selected Annotation, or
    /// with none selected the active tool's, is a Rectangle or an Oval.
    var fillApplies: Bool {
        if let supports = toolbarState.selectionSupportsFill { return supports }
        return currentTool.annotationKind.flatMap(AnnotationKinds.kind)?.supportsFill == true
    }

    /// Whether the fill the user sees chosen is solid: the selected Annotation's, else the one
    /// new Annotations get.
    var fillIsSolid: Bool {
        toolbarState.selectionSupportsFill == true ? toolbarState.selectionFilled : annotationStyle.filled
    }

    /// Outline or solid fill: for the selected Rectangle or Oval, and for the next ones.
    func setAnnotationFilled(_ filled: Bool) {
        annotationStyle.filled = filled
        AnnotationSettings.filled = filled
        restyleSelection(where: { $0.supportsFill }) { $0.filled = filled }
    }

    /// The width in points, for the selected Annotation and for the next ones of its group: the
    /// line width (Arrow, Rectangle, Oval) or the Highlighter's thickness, each remembered
    /// apart. Each call records one Undo step for the selected Annotation: a control that
    /// changes it continuously (a slider) brackets the changes with `document.edit { $0.begin() }`
    /// and `$0.end()`.
    func setAnnotationWidth(_ width: CGFloat) {
        let choice = activeWidthChoice
        switch choice {
        case .none: return
        case .line:
            annotationStyle.width = width
            AnnotationSettings.width = width
        case .highlighter:
            highlighterWidth = width
            AnnotationSettings.highlighterWidth = width
        }
        restyleSelection(where: { $0.widthChoice == choice }) { $0.width = width }
    }

    /// The Annotation color, for the selected Annotation and for the next ones. One Undo step
    /// per call, like `setAnnotationWidth`.
    func setAnnotationColor(_ color: AnnotationColor) {
        annotationStyle.color = color
        AnnotationSettings.color = color
        if restyleTextBeingEdited({ $0.color = color }) { return }
        restyleSelection { $0.color = color }
    }

    /// The Text size in points, for the selected Text and for the next ones.
    func setAnnotationTextSize(_ size: CGFloat) {
        annotationStyle.textSize = size
        AnnotationSettings.textSize = size
        if restyleTextBeingEdited({ $0.textSize = size }) { return }
        restyleSelection(where: { $0.usesTextSize }) { $0.textSize = size }
    }

    /// Changes the selected Annotation's style as one Undo step (or as part of the gesture a
    /// caller has open), when its kind passes `applies`.
    func restyleSelection(
        where applies: (any AnnotationKind) -> Bool = { _ in true }, _ change: (inout AnnotationStyle) -> Void
    ) {
        guard annotationGesture == nil, let selected = selectedAnnotation,
            let kind = AnnotationKinds.kind(selected.kind), applies(kind)
        else { return }
        var updated = selected
        change(&updated.style)
        guard updated != selected else { return }
        document?.edit { history in
            let apply: (inout DocumentState) -> Void = { state in
                if let index = state.annotations.firstIndex(where: { $0.id == updated.id }) {
                    state.annotations[index] = updated
                }
            }
            if history.isInGesture { history.mutate(apply) } else { history.change(apply) }
        }
    }
}
