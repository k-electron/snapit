import Darwin
import Foundation

/// The Files & Folders switch macOS keeps for a folder. System Settings › Privacy & Security › Files &
/// Folders has one switch per category under snapit, not one per folder: Desktop, Documents and
/// Downloads (and what is inside them), iCloud Drive, Removable Volumes and Network Volumes. A folder
/// in none of them (a project folder, a locked or system-protected one) has no switch to turn on, so
/// the folder Permission guide neither draws nor links one for it.
enum FolderCategory: Equatable {
    case desktop, documents, downloads, iCloudDrive, removableVolumes, networkVolumes

    /// The row's label in System Settings.
    var title: String {
        switch self {
        case .desktop: "Desktop Folder"
        case .documents: "Documents Folder"
        case .downloads: "Downloads Folder"
        case .iCloudDrive: "iCloud Drive"
        case .removableVolumes: "Removable Volumes"
        case .networkVolumes: "Network Volumes"
        }
    }

    /// The home folder categories are relative to: the run's root in test mode, where a folder named
    /// `Documents` under the root stands in for the real one.
    private static var home: String {
        (TestMode.root ?? FileManager.default.homeDirectoryForCurrentUser).resolvingSymlinksInPath().path
    }

    /// The category `path` is in, or nil when macOS has no Files & Folders switch for it. A folder with
    /// the immutable flag (`chflags uchg`) is nil too: it refuses a write with `EPERM` whatever the switch says.
    static func of(path: String) -> FolderCategory? {
        let url = URL(fileURLWithPath: path).resolvingSymlinksInPath()
        let resolved = url.path
        var status = stat()
        if stat(resolved, &status) == 0, status.st_flags & (UInt32(UF_IMMUTABLE) | UInt32(SF_IMMUTABLE)) != 0 { return nil }
        func inside(_ base: String) -> Bool { resolved == base || resolved.hasPrefix(base + "/") }
        let home = Self.home
        if inside(home + "/Desktop") { return .desktop }
        if inside(home + "/Documents") { return .documents }
        if inside(home + "/Downloads") { return .downloads }
        if inside(home + "/Library/Mobile Documents") { return .iCloudDrive }
        if resolved.hasPrefix("/Volumes/") {
            let isLocal = (try? url.resourceValues(forKeys: [.volumeIsLocalKey]).volumeIsLocal) ?? true
            return isLocal ? .removableVolumes : .networkVolumes
        }
        return nil
    }
}
