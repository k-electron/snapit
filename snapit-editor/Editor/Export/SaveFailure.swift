import Foundation

/// Why a Save did not go ahead. The Editor stays open when it happens, so nothing is lost.
enum SaveFailure: Equatable, Sendable {
    /// The Save location can't be written to: a folder macOS protects and the user denied, a
    /// folder that is gone, a read-only volume. `code` is the `errno` the menu bar app got.
    /// The folder Permission guide answers this one, with "Choose another folder".
    case folderNotWritable(folder: String, code: Int32)
    /// Something else stopped the Save.
    case failed(String)
}

/// How a Save ended, per Editor.
enum SaveOutcome: Equatable, Sendable {
    /// The menu bar app has the image and is writing the file; it finishes without the helper.
    case handedOver
    case failed(SaveFailure)
}

/// The signal a failed Save raises. A feature that reacts to a failure (the folder Permission
/// guide) registers once at launch:
///
///     SaveFailureSignal.observe { failure, session in
///         guard case .folderNotWritable(let folder, _) = failure else { return }
///         // show the guide for `folder`, offer "Choose another folder"
///     }
///
/// The Editor `session` is still open and still has its Capture; a retry is `session.startSave()`.
@MainActor
enum SaveFailureSignal {
    typealias Observer = @MainActor (SaveFailure, EditorSession) -> Void

    private static var observers: [Observer] = []
    private static var outcomes: [Int: SaveOutcome] = [:]

    /// Calls `observer` every time a Save fails, in every Editor.
    static func observe(_ observer: @escaping Observer) {
        observers.append(observer)
    }

    /// The latest outcome of a Save in the Editor of Capture `number`.
    static func outcome(captureNumber number: Int) -> SaveOutcome? { outcomes[number] }

    /// True when something is listening, so the Editor need not beep itself.
    static var hasObservers: Bool { !observers.isEmpty }

    static func record(_ outcome: SaveOutcome, captureNumber number: Int, session: EditorSession) {
        outcomes[number] = outcome
        guard case .failed(let failure) = outcome else { return }
        for observer in observers { observer(failure, session) }
    }
}
