import Foundation

/// Test mode's `UserDefaults`: every read and write goes straight to one plist file inside the
/// run's root, under a file lock. The system's own preferences are never read or written.
///
/// A `UserDefaults` made from a file path keeps what it loaded: a running process does not see
/// another process's write, and its own write over a key it loaded from the file does not show in
/// its own reads. Settings (in the Editor helper) and the Area flow, Save and Shortcuts (in the
/// menu bar app) must agree at once, as they do through the real domain, so this store reads the
/// file every time. The plist is small and written by hand-driven commands only.
nonisolated final class FileBackedDefaults: UserDefaults {
    private let file: URL
    private let lockFile: URL

    init?(file: URL) {
        self.file = file
        self.lockFile = file.appendingPathExtension("lock")
        // Every accessor below is overridden, so this suite is never used; it is a path inside the
        // run's root (never a system domain) so that an accessor missed here still stays in the root.
        super.init(suiteName: file.deletingLastPathComponent().appendingPathComponent("defaults-unused").path)
    }

    // MARK: File access

    private func withLock<T>(_ body: () -> T) -> T {
        let descriptor = open(lockFile.path, O_CREAT | O_RDWR, 0o600)
        if descriptor >= 0 { flock(descriptor, LOCK_EX) }
        defer { if descriptor >= 0 { flock(descriptor, LOCK_UN); close(descriptor) } }
        return body()
    }

    private func load() -> [String: Any] {
        guard let data = try? Data(contentsOf: file),
            let object = try? PropertyListSerialization.propertyList(from: data, format: nil),
            let dictionary = object as? [String: Any]
        else { return [:] }
        return dictionary
    }

    private func update(_ change: (inout [String: Any]) -> Void) {
        withLock {
            var values = load()
            change(&values)
            guard let data = try? PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0)
            else { return }
            try? data.write(to: file, options: .atomic)
        }
    }

    // MARK: Reading

    override func object(forKey defaultName: String) -> Any? {
        withLock { load()[defaultName] }
    }

    override func string(forKey defaultName: String) -> String? {
        switch object(forKey: defaultName) {
        case let text as String: text
        case let number as NSNumber: number.stringValue
        default: nil
        }
    }

    override func bool(forKey defaultName: String) -> Bool {
        (object(forKey: defaultName) as? NSNumber)?.boolValue ?? false
    }

    override func integer(forKey defaultName: String) -> Int {
        (object(forKey: defaultName) as? NSNumber)?.intValue ?? 0
    }

    override func double(forKey defaultName: String) -> Double {
        (object(forKey: defaultName) as? NSNumber)?.doubleValue ?? 0
    }

    override func float(forKey defaultName: String) -> Float {
        (object(forKey: defaultName) as? NSNumber)?.floatValue ?? 0
    }

    override func array(forKey defaultName: String) -> [Any]? { object(forKey: defaultName) as? [Any] }
    override func stringArray(forKey defaultName: String) -> [String]? { object(forKey: defaultName) as? [String] }
    override func dictionary(forKey defaultName: String) -> [String: Any]? {
        object(forKey: defaultName) as? [String: Any]
    }
    override func data(forKey defaultName: String) -> Data? { object(forKey: defaultName) as? Data }

    override func dictionaryRepresentation() -> [String: Any] {
        withLock { load() }
    }

    // MARK: Writing

    override func set(_ value: Any?, forKey defaultName: String) {
        update { $0[defaultName] = value }
    }

    override func set(_ value: Int, forKey defaultName: String) { set(NSNumber(value: value), forKey: defaultName) }
    override func set(_ value: Float, forKey defaultName: String) { set(NSNumber(value: value), forKey: defaultName) }
    override func set(_ value: Double, forKey defaultName: String) { set(NSNumber(value: value), forKey: defaultName) }
    override func set(_ value: Bool, forKey defaultName: String) { set(NSNumber(value: value), forKey: defaultName) }
    override func set(_ url: URL?, forKey defaultName: String) { set(url?.absoluteString, forKey: defaultName) }

    override func removeObject(forKey defaultName: String) {
        update { $0.removeValue(forKey: defaultName) }
    }
}
