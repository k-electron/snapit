import CoreGraphics

/// Typing a Text. The Text tool (and a double click on a Text) opens a text view over the canvas;
/// a click away, Esc, another tool, Copy or closing commits it as one Undo step. A Text with
/// nothing in it is never made (or, when it was being edited, is removed).
extension EditorSession {
    var isEditingText: Bool { canvas?.textEditing != nil }
    var textEditingCanUndo: Bool { canvas?.textEditing?.canUndo == true }
    var textEditingCanRedo: Bool { canvas?.textEditing?.canRedo == true }

    /// The Text tool's press: edits the Text under the pointer, or starts a new one there.
    func beginText(at point: CGPoint) {
        guard document != nil, annotationGesture == nil, !isEditingText else { return }
        if let hit = annotation(at: point), hit.kind == .text {
            editText(hit)
        } else {
            openTextView(for: Annotation(id: 0, kind: .text, start: point, end: point, style: annotationStyle), isNew: true)
        }
    }

    private func editText(_ annotation: Annotation) {
        selectAnnotation(annotation.id)
        canvas?.annotationLayers.setHidden(true, id: annotation.id)
        openTextView(for: annotation, isNew: false)
    }

    private func openTextView(for draft: Annotation, isNew: Bool) {
        guard let canvas, let host = canvas.textHost else { return }
        if isNew { selectAnnotation(nil) }
        let editor = TextEditingController(draft: draft, isNew: isNew, canvas: canvas, host: host)
        editor.onEnd = { [weak self] in self?.commitTextEditing(refocus: false) }
        editor.onChange = { [weak self] in self?.textEditRevision &+= 1 }
        canvas.textEditing = editor
        textEditRevision &+= 1
    }

    /// The canvas's first look at a press. A click while a text is typed commits it and goes no
    /// further (it never starts another text box); a double click on a Text edits it. Returns
    /// true when it took the click.
    func consumesPointerDown(at point: CGPoint, clickCount: Int) -> Bool {
        if isEditingText {
            commitTextEditing()
            return true
        }
        if clickCount >= 2, !isEyedropperActive, annotationGesture == nil, let hit = annotation(at: point), hit.kind == .text {
            editText(hit)
            return true
        }
        return false
    }

    /// Ends the typing: the text becomes (or updates, or removes) an Annotation. Returns whether
    /// there was a text being typed.
    @discardableResult
    func commitTextEditing(refocus: Bool = true) -> Bool {
        guard let canvas, let editor = canvas.textEditing else { return false }
        var annotation = editor.draft
        annotation.text = editor.text
        let wasNew = editor.isNew
        canvas.textEditing = nil
        editor.tearDown()
        textEditRevision &+= 1
        canvas.annotationLayers.setHidden(false, id: annotation.id)
        if refocus { canvas.window?.makeFirstResponder(canvas) }
        guard let document else { return true }
        if wasNew {
            if !annotation.text.isEmpty {
                document.edit { history in
                    annotation.id = history.makeID()
                    history.change { $0.annotations.append(annotation) }
                }
                selectAnnotation(annotation.id)
            }
        } else if annotation.text.isEmpty {
            document.edit { history in history.change { $0.annotations.removeAll { $0.id == annotation.id } } }
            selectAnnotation(nil)
        } else {
            if document.history.annotation(id: annotation.id) != annotation {
                document.edit { history in
                    history.change { state in
                        if let index = state.annotations.firstIndex(where: { $0.id == annotation.id }) {
                            state.annotations[index] = annotation
                        }
                    }
                }
            }
            selectAnnotation(annotation.id)
        }
        return true
    }

    /// ⌘Z while a text is typed: takes back typing; false when there is none to take back (then
    /// the text is committed and Undo goes on to the Annotations).
    func undoTextEditing() -> Bool {
        guard let editor = canvas?.textEditing else { return false }
        if editor.canUndo {
            editor.undo()
            textEditRevision &+= 1
            return true
        }
        commitTextEditing()
        return false
    }

    func redoTextEditing() -> Bool {
        guard let editor = canvas?.textEditing else { return false }
        if editor.canRedo {
            editor.redo()
            textEditRevision &+= 1
            return true
        }
        // Nothing typed to put back: the text is committed and Redo goes on to the Annotations,
        // as Undo does.
        commitTextEditing()
        return false
    }

    /// A color or text size chosen while a text is typed changes the text on screen at once.
    /// Returns true when it did.
    func restyleTextBeingEdited(_ change: (inout AnnotationStyle) -> Void) -> Bool {
        guard let editor = canvas?.textEditing else { return false }
        editor.restyle(change)
        return true
    }
}
