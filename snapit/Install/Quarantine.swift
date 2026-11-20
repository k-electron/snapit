import Foundation

/// The `com.apple.quarantine` extended attribute: `<flags in hex>;<time>;<agent>;<uuid>`.
enum Quarantine {
    static let attribute = "com.apple.quarantine"
    /// Set by macOS when the user approved the app with Open Anyway (`0083` becomes `00c3`).
    static let userApprovedFlag: UInt32 = 0x40

    static func value(at path: String) -> String? {
        var buffer = [CChar](repeating: 0, count: 512)
        let length = getxattr(path, attribute, &buffer, buffer.count - 1, 0, XATTR_NOFOLLOW)
        return length >= 0 ? String(decoding: buffer.prefix(length).map { UInt8(bitPattern: $0) }, as: UTF8.self) : nil
    }

    /// True when quarantine does not stand between the user and this app: it carries none, or
    /// the user already approved it with Open Anyway. snapit strips quarantine only from an app
    /// that passes this, so a copy macOS has not let through yet is never waved through.
    static func isApproved(at path: String) -> Bool {
        guard let attribute = value(at: path) else { return true }
        guard let flagsField = attribute.split(separator: ";", omittingEmptySubsequences: false).first,
            let flags = UInt32(flagsField, radix: 16)
        else { return false }
        return flags & userApprovedFlag != 0
    }

    /// Every file and folder under `root`, `root` first.
    static func items(under root: URL) -> [String] {
        [root.path] + (FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?.compactMap { ($0 as? URL)?.path } ?? [])
    }

    /// How many items under `root` still carry quarantine.
    static func flaggedCount(under root: URL) -> Int {
        items(under: root).filter { value(at: $0) != nil }.count
    }

    /// Removes quarantine from `root` and everything inside it. Returns how many items had it.
    @discardableResult
    static func strip(under root: URL) -> Int {
        var removed = 0
        for path in items(under: root) where value(at: path) != nil {
            if removexattr(path, attribute, XATTR_NOFOLLOW) == 0 { removed += 1 }
        }
        return removed
    }
}
