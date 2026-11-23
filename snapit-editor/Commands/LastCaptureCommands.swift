import AppKit

nonisolated extension SocketCommand {
    /// `last-capture-writes`: `written=<n> dropped=<n>`, how many state files this helper has
    /// written and how many queued writes it dropped as stale. Test mode only.
    static let lastCaptureWrites = SocketCommand("last-capture-writes")
    /// `last-capture-hold on|off`: holds every state write in front of the serial queue until
    /// released, so a run can make a queued write stale. Test mode only.
    static let lastCaptureHold = SocketCommand("last-capture-hold")
    /// `last-capture-roundtrip`: stores a history holding one Annotation of every kind in
    /// `AnnotationKinds.all` (found by iterating it), one of a kind no snapit knows, a crop and more
    /// Undo steps than the cap, through the state file's encoder and decoder, and replies
    /// `ok kinds=<ids>` or `error <what differed>`. Test mode only.
    static let lastCaptureRoundtrip = SocketCommand("last-capture-roundtrip")
    /// `annotation-kinds`: the ids in `AnnotationKinds.all`, one per line. Test mode only.
    static let annotationKinds = SocketCommand("annotation-kinds")
    /// `editor-inject-kinds <N>`: adds one Annotation of every kind in `AnnotationKinds.all` to
    /// Editor N, each its own Undo step, side by side. Test mode only.
    static let editorInjectKinds = SocketCommand("editor-inject-kinds")
    /// `editor-state-crop <N> get` or `set <x> <y> <width> <height>`: Editor N's crop rectangle in
    /// image points (`none` for the whole Capture), as one Undo step. There is no Crop tool in this
    /// command's way: it stands in for one, to check the crop is stored. Test mode only.
    static let editorStateCrop = SocketCommand("editor-state-crop")
    /// `editor-menu-quit`: chooses "Quit snapit" in the helper's own menu (it replies at once; the
    /// quit goes on in the background). Test mode only.
    static let editorMenuQuit = SocketCommand("editor-menu-quit")
    /// `editor-front`: the number of the Editor whose window is frontmost of the helper's windows,
    /// or `none`. A scripted run never activates the helper, so no window is key; the order is what
    /// "brought forward" shows. Test mode only.
    static let editorFront = SocketCommand("editor-front")
    /// `reopen-notice`: `shown <message>` while "That Capture couldn't be reopened." is on
    /// screen, else `none`. Test mode only.
    static let reopenNotice = SocketCommand("reopen-notice")
    /// `reopen-notice-close`: presses the notice's OK button. Test mode only.
    static let reopenNoticeClose = SocketCommand("reopen-notice-close")
}

extension SocketCommandRegistry {
    /// The Last Capture's commands the helper answers: Reopen, and what stopping needs.
    func registerLastCaptureCommands() {
        register(.reopenCapture) { request in
            guard let number = request.arguments.first.flatMap(Int.init) else { return "error reopen-capture <number>" }
            do {
                try await EditorSessions.shared.reopen(captureNumber: number)
                CATransaction.flush()
                return "ok"
            } catch ReopenError.superseded {
                // A newer Capture (or Delete Capture) got there first: nothing to reopen, nothing to say.
                return "error superseded"
            } catch {
                NSLog("snapit Editor: could not reopen Capture \(number): \(error)")
                // The menu bar app never opens a window: the helper tells the user.
                ReopenNotice.show()
                return "error could-not-reopen"
            }
        }
        register(.saveLastCapture) { _ in
            EditorSessions.shared.lastCaptureSession?.writeLastCaptureNow()
            return "ok"
        }
        // Quit (the `quit` command and the helper's own "Quit snapit"): nothing more is written for
        // the Last Capture, and the quit goes on only when no write is still running. The menu bar
        // app removes the Capture's files after that.
        QuitPreparation.steps.append {
            LastCaptureStore.shared.supersede()
            await LastCaptureStore.shared.fence()
        }
        registerLastCaptureTestCommands()
    }

    private func registerLastCaptureTestCommands() {
        guard TestMode.isActive else { return }
        register(.lastCaptureWrites) { _ in
            "written=\(LastCaptureStore.shared.writtenCount) dropped=\(LastCaptureStore.shared.droppedCount)"
        }
        register(.lastCaptureHold) { request in
            guard let mode = request.arguments.first, ["on", "off"].contains(mode) else { return "error last-capture-hold on|off" }
            LastCaptureStore.shared.setHeld(mode == "on")
            return "ok"
        }
        register(.annotationKinds) { _ in
            AnnotationKinds.all.map(\.id.rawValue).joined(separator: "\n")
        }
        register(.lastCaptureRoundtrip) { _ in Self.roundtrip() }
        register(.editorInjectKinds) { request in
            guard let session = Self.session(request) else { return "error editor-inject-kinds <N>" }
            for (index, kind) in AnnotationKinds.all.enumerated() {
                session.document?.edit { history in
                    let annotation = kind.sampleAnnotation(
                        id: history.makeID(), origin: CGPoint(x: 20 + CGFloat(index) * 36, y: 20), index: index)
                    history.change { $0.annotations.append(annotation) }
                }
            }
            return "ok"
        }
        register(.editorStateCrop) { request in
            guard let session = Self.session(request), request.arguments.count >= 2, let document = session.document
            else { return "error editor-state-crop <N> get|set <x> <y> <width> <height>" }
            if request.arguments[1] == "set" {
                let numbers = request.arguments.dropFirst(2).compactMap(Double.init)
                guard numbers.count == 4 else { return "error editor-state-crop <N> set <x> <y> <width> <height>" }
                let crop = CGRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])
                document.edit { $0.change { $0.crop = crop } }
                return "ok"
            }
            guard let crop = document.history.state.crop else { return "none" }
            return [crop.minX, crop.minY, crop.width, crop.height].map { String(format: "%.1f", $0) }.joined(separator: " ")
        }
        register(.editorMenuQuit) { _ in
            guard let delegate = NSApp.delegate as? HelperDelegate else { return "error no helper delegate" }
            delegate.quitSnapit(nil)
            return "ok"
        }
        register(.editorFront) { _ in
            let sessions = EditorSessions.shared.sessions
            let front = NSApp.orderedWindows.compactMap { window in sessions.first { $0.value.window === window }?.key }.first
            return front.map(String.init) ?? "none"
        }
        register(.reopenNotice) { _ in
            ReopenNotice.current.map { _ in "shown \(ReopenNotice.message)" } ?? "none"
        }
        register(.reopenNoticeClose) { _ in
            ReopenNotice.current?.close()
            return "ok"
        }
    }

    private static func session(_ request: SocketRequest) -> EditorSession? {
        request.arguments.first.flatMap(Int.init).flatMap { EditorSessions.shared.session(captureNumber: $0) }
    }

    private static func roundtrip() -> String {
        var history = AnnotationHistory()
        // One sample of every kind in the registry (each kind says what its fields are), and one of
        // a kind no snapit knows.
        var samples = AnnotationKinds.all.enumerated().map { index, kind in
            kind.sampleAnnotation(id: 0, origin: CGPoint(x: 5.5 + CGFloat(index) * 3, y: 7.5), index: index)
        }
        var unknown = AnnotationKinds.all[0].sampleAnnotation(id: 0, origin: CGPoint(x: 9.25, y: 3), index: samples.count)
        unknown.kind = AnnotationKindID("kind-from-a-newer-snapit")
        samples.append(unknown)
        let kinds = samples.map(\.kind)
        for var annotation in samples {
            annotation.id = history.makeID()
            let sample = annotation
            history.change { $0.annotations.append(sample) }
        }
        history.change { $0.crop = CGRect(x: 10, y: 12.5, width: 100, height: 80.25) }
        // More steps than the cap keeps.
        for step in 0..<(AnnotationHistory.maxSteps + 20) {
            history.change { $0.annotations[0].end.x = CGFloat(50 + step) }
        }
        history.undo()
        let state = LastCaptureState(history: history, exported: true)
        do {
            let decoded = try LastCaptureStateFile.decode(LastCaptureStateFile.encode(state))
            guard decoded == state else { return "error the decoded state differs from the stored one" }
            // The cap is full, and one step was undone.
            guard decoded.history.undoSteps.count == AnnotationHistory.maxSteps - 1 else {
                return "error \(decoded.history.undoSteps.count) Undo steps came back, not \(AnnotationHistory.maxSteps - 1)"
            }
            guard decoded.history.redoSteps.count == 1, decoded.exported, decoded.revision == history.revision,
                decoded.history.state.crop == history.state.crop
            else { return "error the revision, the Redo step, the exported flag or the crop was lost" }
            let names = decoded.history.annotations.map(\.kind.rawValue)
            guard names.count == kinds.count, names == kinds.map(\.rawValue) else {
                return "error the kinds came back as \(names)"
            }
            return "ok kinds=" + kinds.map(\.rawValue).joined(separator: ",")
        } catch {
            return "error \(error)"
        }
    }
}
