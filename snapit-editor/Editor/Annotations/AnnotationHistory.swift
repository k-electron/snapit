import CoreGraphics

/// Everything Undo restores: the Annotations in the order they are drawn, and the crop.
/// Snapshots of it are the Undo history, which is why Annotations are value types.
nonisolated struct DocumentState: Codable, Equatable, Sendable {
    var annotations: [Annotation] = []
    /// The crop rectangle in image points; nil for the whole Capture. Set by the Crop tool.
    var crop: CGRect?

    init(annotations: [Annotation] = [], crop: CGRect? = nil) {
        self.annotations = annotations
        self.crop = crop
    }

    private enum CodingKeys: String, CodingKey { case annotations, crop }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        annotations = try container.decodeIfPresent([Annotation].self, forKey: .annotations) ?? []
        crop = try container.decodeIfPresent(CGRect.self, forKey: .crop)
    }
}

/// A Capture's Annotations and crop with their snapshot Undo and Redo history. It has no view
/// and no AppKit in it, and it is `Codable`, so the Last Capture can store it and bring the
/// Editor back exactly as it was.
///
/// A gesture brackets its changes: `begin()`, any number of `mutate`, then `end()`, which
/// records one Undo step if the state is different, or `abort()`, which puts it back. A change
/// that is complete in one call is `change(_:)`. `revision` goes up with every recorded
/// change, every Undo and every Redo.
///
/// Fields added later are decoded with `decodeIfPresent` and a default, so a history written by
/// an older snapit still opens.
nonisolated struct AnnotationHistory: Codable, Equatable, Sendable {
    /// Undo steps (and Redo steps) kept; the oldest go first.
    static let maxSteps = 100

    private(set) var state = DocumentState()
    private(set) var undoSteps: [DocumentState] = []
    private(set) var redoSteps: [DocumentState] = []
    private(set) var revision = 0
    private var nextID = 1
    /// The state before the gesture in progress. Not stored.
    private var pending: DocumentState?

    init() {}

    private enum CodingKeys: String, CodingKey { case state, undoSteps, redoSteps, revision, nextID }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        state = try container.decodeIfPresent(DocumentState.self, forKey: .state) ?? DocumentState()
        undoSteps = Array((try container.decodeIfPresent([DocumentState].self, forKey: .undoSteps) ?? []).suffix(Self.maxSteps))
        redoSteps = Array((try container.decodeIfPresent([DocumentState].self, forKey: .redoSteps) ?? []).suffix(Self.maxSteps))
        revision = try container.decodeIfPresent(Int.self, forKey: .revision) ?? 0
        let highest = state.annotations.map(\.id).max() ?? 0
        nextID = max(try container.decodeIfPresent(Int.self, forKey: .nextID) ?? 1, highest + 1)
    }

    var annotations: [Annotation] { state.annotations }
    var canUndo: Bool { !undoSteps.isEmpty }
    var canRedo: Bool { !redoSteps.isEmpty }
    var isInGesture: Bool { pending != nil }

    func annotation(id: Int) -> Annotation? { state.annotations.first { $0.id == id } }

    /// A new Annotation number, never used before in this document.
    mutating func makeID() -> Int {
        defer { nextID += 1 }
        return nextID
    }

    // MARK: Changing

    /// Starts a gesture: its changes become one Undo step.
    mutating func begin() {
        if pending == nil { pending = state }
    }

    /// Changes the state inside a gesture (or alone, until the next `end`).
    mutating func mutate(_ change: (inout DocumentState) -> Void) {
        change(&state)
    }

    /// Ends the gesture. Records an Undo step, and drops the Redo steps, only when something
    /// changed; returns whether it did.
    @discardableResult
    mutating func end() -> Bool {
        guard let before = pending else { return false }
        pending = nil
        guard before != state else { return false }
        undoSteps.append(before)
        trim(&undoSteps)
        redoSteps.removeAll()
        revision += 1
        return true
    }

    /// Ends the gesture and puts the state back as it was.
    mutating func abort() {
        guard let before = pending else { return }
        pending = nil
        state = before
    }

    /// One whole change as one Undo step.
    @discardableResult
    mutating func change(_ change: (inout DocumentState) -> Void) -> Bool {
        begin()
        mutate(change)
        return end()
    }

    @discardableResult
    mutating func undo() -> Bool {
        guard pending == nil, let previous = undoSteps.popLast() else { return false }
        redoSteps.append(state)
        trim(&redoSteps)
        state = previous
        revision += 1
        return true
    }

    @discardableResult
    mutating func redo() -> Bool {
        guard pending == nil, let next = redoSteps.popLast() else { return false }
        undoSteps.append(state)
        trim(&undoSteps)
        state = next
        revision += 1
        return true
    }

    private func trim(_ steps: inout [DocumentState]) {
        if steps.count > Self.maxSteps { steps.removeFirst(steps.count - Self.maxSteps) }
    }
}
