import Foundation

/// The Timed Capture countdown, in whole seconds. It is remembered across launches without a
/// Settings entry: the Action bar's slider shows it and writes it.
enum TimedCaptureSettings {
    static let secondsKey = "timedCaptureSeconds"
    static let range = 1...10
    static let defaultSeconds = 3

    /// The stored seconds, kept within 1-10; 3 when nothing usable is stored. A string such as "7"
    /// counts too, which is how the scripted run writes defaults.
    static var seconds: Int {
        get {
            let value = AppDefaults.store.object(forKey: secondsKey)
            let stored = (value as? Int) ?? (value as? String).flatMap { Int($0) }
            return stored.map { min(range.upperBound, max(range.lowerBound, $0)) } ?? defaultSeconds
        }
        set {
            AppDefaults.store.set(min(range.upperBound, max(range.lowerBound, newValue)), forKey: secondsKey)
        }
    }
}
