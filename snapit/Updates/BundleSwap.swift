import Darwin
import Foundation

/// Puts a newer copy of snapit in place of the installed one while the installed one still runs.
nonisolated enum BundleSwap {
    enum Failure: Error, CustomStringConvertible {
        case failed(String)

        var description: String {
            switch self {
            case .failed(let reason): "snapit could not replace itself: \(reason)"
            }
        }
    }

    /// Trades `staged` and `installed` in one step (`renamex_np` with `RENAME_SWAP`): at no moment is
    /// there no snapit at `installed`. Afterwards `staged` holds the old copy. A volume that cannot
    /// swap moves the old copy aside, into the staged copy's folder, and the new one in; if that
    /// fails halfway, the old copy goes back. Either way the old copy ends up in the staging folder,
    /// and a failure leaves `installed` as it was.
    static func swap(staged: URL, intoPlaceOf installed: URL) throws {
        if renamex_np(staged.path, installed.path, UInt32(RENAME_SWAP)) == 0 { return }
        let code = errno
        guard code == ENOTSUP || code == EINVAL else { throw Failure.failed(String(cString: strerror(code))) }

        let aside = staged.deletingLastPathComponent().appendingPathComponent("previous.app", isDirectory: true)
        guard rename(installed.path, aside.path) == 0 else { throw Failure.failed(String(cString: strerror(errno))) }
        guard rename(staged.path, installed.path) == 0 else {
            let reason = String(cString: strerror(errno))
            rename(aside.path, installed.path)
            throw Failure.failed(reason)
        }
    }
}
