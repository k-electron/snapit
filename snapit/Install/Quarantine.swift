import Foundation

/// The `com.apple.quarantine` extended attribute: `<flags in hex>;<time>;<agent>;<uuid>`.
nonisolated enum Quarantine {
    static let attribute = "com.apple.quarantine"
    /// Set by macOS when the user approved the app with Open Anyway (`0083` becomes `00c3`).
    static let userApprovedFlag: UInt32 = 0x40

    enum State: Equatable {
        /// The item carries no quarantine attribute (`ENOATTR`).
        case none
        case present(String)
        /// The attribute could not be read (any error but `ENOATTR`). Never read as "none".
        case unreadable
    }

    static func state(at path: String) -> State {
        let size = getxattr(path, attribute, nil, 0, 0, XATTR_NOFOLLOW)
        if size < 0 { return errno == ENOATTR ? .none : .unreadable }
        var buffer = [UInt8](repeating: 0, count: size)
        let length = getxattr(path, attribute, &buffer, size, 0, XATTR_NOFOLLOW)
        if length < 0 { return errno == ENOATTR ? .none : .unreadable }
        return .present(String(decoding: buffer.prefix(length), as: UTF8.self))
    }

    /// True when quarantine does not stand between the user and this app: it carries none, or
    /// the user already approved it with Open Anyway. snapit strips quarantine only from an app
    /// that passes this, so a copy macOS has not let through yet is never waved through, and an
    /// attribute that cannot be read does not count as approved.
    static func isApproved(at path: String) -> Bool {
        switch state(at: path) {
        case .none: return true
        case .unreadable: return false
        case .present(let attribute):
            guard let flagsField = attribute.split(separator: ";", omittingEmptySubsequences: false).first,
                let flags = UInt32(flagsField, radix: 16)
            else { return false }
            return flags & userApprovedFlag != 0
        }
    }

    /// Every file and folder under `root`, `root` first.
    static func items(under root: URL) -> [String] {
        [root.path] + (FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?.compactMap { ($0 as? URL)?.path } ?? [])
    }

    /// How many items under `root` still carry quarantine, or could not be read.
    static func flaggedCount(under root: URL) -> Int {
        items(under: root).filter { state(at: $0) != .none }.count
    }

    /// Removes quarantine from `root` and everything inside it. Returns how many items had it.
    @discardableResult
    static func strip(under root: URL) -> Int {
        var removed = 0
        for path in items(under: root) where state(at: path) != .none {
            if removexattr(path, attribute, XATTR_NOFOLLOW) == 0 { removed += 1 }
        }
        return removed
    }
}
