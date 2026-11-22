import Darwin
import Foundation

/// Puts a newer copy of snapit in place of the installed one while the installed one still runs.
nonisolated enum BundleSwap {
    enum Failure: Error, CustomStringConvertible {
        /// Nothing changed: `installed` is as it was.
        case failed(String)
        /// The old copy was moved aside and the new one could not go in, and the old one could not
        /// be moved back: nothing is at `installed`, and `oldCopy` is the snapit that was there.
        case notRestored(reason: String, oldCopy: URL)

        var description: String {
            switch self {
            case .failed(let reason): "snapit could not replace itself: \(reason)"
            case .notRestored(let reason, let oldCopy):
                "snapit could not replace itself (\(reason)) and could not put its old copy back; it is at \(oldCopy.path)"
            }
        }
    }

    /// Trades `staged` and `installed` in one step (`renamex_np` with `RENAME_SWAP`): at no moment is
    /// there no snapit at `installed`. Afterwards `staged` holds the old copy. A volume that cannot
    /// swap moves the old copy aside, into the staged copy's folder, and the new one in; if that
    /// fails halfway, the old copy goes back. Either way the old copy ends up in the staging folder,
    /// and a failure leaves `installed` as it was, unless the old copy cannot go back: then the
    /// failure is `notRestored`, and the caller must keep the staging folder, which holds that copy.
    static func swap(staged: URL, intoPlaceOf installed: URL) throws {
        if renamex_np(staged.path, installed.path, UInt32(RENAME_SWAP)) == 0 { return }
        let code = errno
        guard code == ENOTSUP || code == EINVAL else { throw Failure.failed(String(cString: strerror(code))) }

        let aside = staged.deletingLastPathComponent().appendingPathComponent(UpdateStaging.oldCopyName, isDirectory: true)
        guard rename(installed.path, aside.path) == 0 else { throw Failure.failed(String(cString: strerror(errno))) }
        guard rename(staged.path, installed.path) == 0 else {
            let reason = String(cString: strerror(errno))
            guard rename(aside.path, installed.path) == 0 else { throw Failure.notRestored(reason: reason, oldCopy: aside) }
            throw Failure.failed(reason)
        }
    }
}
