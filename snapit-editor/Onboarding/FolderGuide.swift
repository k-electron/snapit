import AppKit

/// Where the folder Permission guide is shown from.
///
/// - A Save from an Editor whose Save location can't be written to (`SaveFailureSignal`): the Editor
///   stays open, the guide says why, and "Try again" or choosing another folder saves from it.
/// - The menu bar app asking over the socket (`show-permission-guide folder <errno|none> <folder>`)
///   for a Save that failed after its hand-over: no Editor is named, so there is nothing to retry.
@MainActor
enum FolderGuide {
    /// Listens for failed Saves. Called once, when the helper starts serving commands.
    static func register() {
        SaveFailureSignal.observeHandedOver { session in saved(from: session) }
        SaveFailureSignal.observe { failure, session in
            switch failure {
            case .folderNotWritable(let folder, let code):
                show(folder: folder, code: code, session: session)
            case .failed:
                // Not about the folder: nothing to explain, so the Editor's old beep stands in.
                if !TestMode.isActive { NSSound.beep() }
            }
        }
    }

    /// A Save from the Editor the guide is about got through (the retry, or ⌘S after the user fixed the
    /// folder): the guide has done its job and closes.
    private static func saved(from session: EditorSession) {
        guard let open = PermissionGuideWindow.current(.folder)?.content as? FolderGuideModel, open.isAbout(session) else { return }
        open.onFinished?()
    }

    /// Shows the guide, or updates the open one with the new failure.
    static func show(folder: String, code: Int32?, session: EditorSession?) {
        if let open = PermissionGuideWindow.current(.folder)?.content as? FolderGuideModel {
            open.update(folder: folder, code: code, session: session)
        }
        PermissionGuideWindow.show(.folder) { FolderGuideModel(folder: folder, code: code, session: session) }
    }

    /// The details of `show-permission-guide folder <errno|none> <folder>`.
    static func show(arguments: [String]) -> String {
        guard arguments.count >= 2, arguments[0] == "none" || Int32(arguments[0]) != nil else {
            return "error show-permission-guide folder <errno|none> <folder>"
        }
        show(folder: arguments[1], code: Int32(arguments[0]), session: nil)
        return "ok"
    }
}
