import Foundation

/// What `statfs` says about the volume a path is on.
struct VolumeInfo: Equatable {
    var fileSystem: String
    var mountedFrom: String
    var mountPoint: String
    var isReadOnly: Bool
}

/// Where volume facts come from. The real one is `statfs`; the scripted run adds fake volumes.
protocol VolumeInspecting {
    func volume(at path: String) -> VolumeInfo?
}

struct SystemVolumes: VolumeInspecting {
    func volume(at path: String) -> VolumeInfo? {
        var stats = statfs()
        guard statfs(path, &stats) == 0 else { return nil }
        return VolumeInfo(
            fileSystem: Self.string(stats.f_fstypename), mountedFrom: Self.string(stats.f_mntfromname),
            mountPoint: Self.string(stats.f_mntonname), isReadOnly: (stats.f_flags & UInt32(MNT_RDONLY)) != 0)
    }

    private static func string<T>(_ field: T) -> String {
        var field = field
        return withUnsafeBytes(of: &field) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
    }
}

/// Paths with symlinks resolved the way the kernel reports them (`/tmp` is `/private/tmp`).
/// `URL.resolvingSymlinksInPath()` is not used: it maps `/private/tmp` back to `/tmp`.
enum RealPath {
    /// Resolves the longest existing ancestor of `path` with `realpath(3)` and appends the rest.
    static func of(_ path: String) -> String {
        var existing = path
        var rest: [String] = []
        while existing != "/", !existing.isEmpty {
            if let resolved = realpath(existing, nil) {
                defer { free(resolved) }
                return String(cString: resolved) + rest.reversed().map { "/" + $0 }.joined()
            }
            rest.append((existing as NSString).lastPathComponent)
            existing = (existing as NSString).deletingLastPathComponent
        }
        return path
    }
}

/// What snapit should do about the place it runs from.
enum InstallPlan: Equatable {
    /// Running from a normal place.
    case stay
    /// Offer "Move snapit to Applications": copy `source` there.
    case move(source: URL)
    /// macOS runs the copy in Applications from a temporary location: strip quarantine from
    /// `copy` and relaunch it in place.
    case fixInPlace(copy: URL)

    var name: String {
        switch self {
        case .stay: "none"
        case .move: "move"
        case .fixInPlace: "fix-in-place"
        }
    }
}

/// Where this copy of snapit runs from, read on every launch.
struct InstallLocation: Equatable {
    var bundlePath: String
    /// True when macOS runs the app from an `AppTranslocation` path.
    var translocated: Bool
    /// The app's real place: the nullfs source when translocated, else the bundle path.
    var originPath: String
    /// The volume the origin is on.
    var volume: VolumeInfo?
    /// Disk images mount below this folder (`/Volumes`).
    var volumesFolder: String

    /// True when the origin sits on a read-only volume mounted below the volumes folder: a mounted disk image.
    var onDiskImage: Bool {
        guard let volume, volume.isReadOnly else { return false }
        return volume.mountPoint.hasPrefix(volumesFolder + "/")
    }

    static func detect(bundlePath: String, volumes: any VolumeInspecting, volumesFolder: String) -> InstallLocation {
        let translocated = bundlePath.contains("/AppTranslocation/")
        let own = volumes.volume(at: bundlePath)
        var origin = bundlePath
        // A translocated bundle is a read-only nullfs mount whose "from" is the original path.
        if translocated, let own, own.fileSystem == "nullfs" { origin = own.mountedFrom }
        let volume = translocated ? (volumes.volume(at: origin) ?? own) : own
        return InstallLocation(
            bundlePath: bundlePath, translocated: translocated, originPath: origin, volume: volume,
            volumesFolder: volumesFolder)
    }

    /// The plan for this location. `fileExists` says whether the origin is still there.
    func plan(applicationsFolder: URL, fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) })
        -> InstallPlan
    {
        guard translocated || onDiskImage else { return .stay }
        let origin = fileExists(originPath) ? originPath : bundlePath
        let originURL = URL(fileURLWithPath: origin)
        let inApplications =
            RealPath.of(originURL.deletingLastPathComponent().path) == RealPath.of(applicationsFolder.path)
        if translocated, !onDiskImage, inApplications { return .fixInPlace(copy: originURL) }
        return .move(source: originURL)
    }
}
