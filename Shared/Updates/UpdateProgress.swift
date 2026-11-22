import Foundation

/// How far the Update the menu bar app is running has got: what the Update window shows while it
/// waits (the progress bar, whether Cancel and close still do anything). The menu bar app owns the
/// Update, so the Editor helper asks for this over the command socket (`update-status`) while its
/// own request, `install-update`, is still waiting for its reply.
///
///     idle                       (no Update is running)
///     downloading <received> <total>    (<total> is `-` until the release says how big the file is)
///     checking                   (the download is being checked and its copy of snapit taken out)
///     swapping                   (the new copy is going in: from here on nothing can stop the Update)
nonisolated enum UpdateProgress: Equatable, Sendable {
    case idle
    /// The release's files are being downloaded: bytes of the disk image received, and its size when known.
    case downloading(received: Int64, total: Int64?)
    case checking
    case swapping

    /// The Update can still be ended with nothing changed: it has not begun to swap.
    var canCancel: Bool {
        switch self {
        case .downloading, .checking: true
        case .idle, .swapping: false
        }
    }

    /// How much of the disk image has arrived, 0 to 100 (rounded); nil when its size is not known.
    var percent: Int? {
        guard case .downloading(let received, let total) = self, let total, total > 0 else { return nil }
        return Int(min(max((received * 100 + total / 2) / total, 0), 100))
    }

    var wire: String {
        switch self {
        case .idle: "idle"
        case .downloading(let received, let total): "downloading \(received) \(total.map(String.init) ?? "-")"
        case .checking: "checking"
        case .swapping: "swapping"
        }
    }

    init?(wire: String) {
        let words = wire.split(separator: " ").map(String.init)
        switch words.first {
        case "idle" where words.count == 1: self = .idle
        case "checking" where words.count == 1: self = .checking
        case "swapping" where words.count == 1: self = .swapping
        case "downloading" where words.count == 3:
            guard let received = Int64(words[1]), received >= 0 else { return nil }
            if words[2] == "-" {
                self = .downloading(received: received, total: nil)
            } else if let total = Int64(words[2]), total >= 0 {
                self = .downloading(received: received, total: total)
            } else {
                return nil
            }
        default: return nil
        }
    }
}
