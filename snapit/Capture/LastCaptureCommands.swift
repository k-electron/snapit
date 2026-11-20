import Foundation

nonisolated extension SocketCommand {
    /// `last-capture`: the Last Capture's number, or `none`. Test mode only.
    static let lastCapture = SocketCommand("last-capture")
    /// `menu-enabled <id>`: `yes` or `no`, whether the menu item with that id is enabled now
    /// (a greyed item is `no`). Test mode only.
    static let menuEnabled = SocketCommand("menu-enabled")
    /// `capture-folder-race`: the next Capture file written finds its (empty) folder removed
    /// between the folder being made and the file being created, as a Delete Capture can do.
    /// Replies `ok`. Test mode only.
    static let captureFolderRace = SocketCommand("capture-folder-race")
}

extension SocketCommandRegistry {
    func registerLastCaptureTestCommands() {
        guard TestMode.isActive else { return }
        register(.lastCapture) { _ in
            LastCapture.shared.number.map(String.init) ?? "none"
        }
        register(.captureFolderRace) { _ in
            CaptureFiles.folderRaceHook = {
                CaptureFiles.folderRaceHook = nil
                rmdir(CaptureFiles.folder.path)
            }
            return "ok"
        }
        register(.menuEnabled) { request in
            guard let id = request.arguments.first,
                let entry = MenuModel.shared.entries.first(where: { $0.id == id })
            else { return "error no menu item \(request.arguments.first ?? "")" }
            return entry.isEnabled ? "yes" : "no"
        }
    }
}
