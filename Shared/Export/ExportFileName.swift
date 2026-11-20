import Foundation

/// The name of an exported file: `snapit-YYYYMMDD-HHMMSS.png`, from the time of the Capture in
/// the user's time zone, so names are short, have no spaces and sort by time. A clash adds
/// `-2`, `-3` and so on before the extension. The pattern is fixed.
nonisolated enum ExportFileName {
    static let pathExtension = "png"

    /// `snapit-20261119-155058` for a Capture taken at that time.
    static func base(captureTime: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "snapit-" + formatter.string(from: captureTime)
    }

    /// The file name for the `attempt`th try: the plain name first, then `-2`, `-3`, ...
    static func fileName(captureTime: Date, attempt: Int = 1) -> String {
        let suffix = attempt > 1 ? "-\(attempt)" : ""
        return base(captureTime: captureTime) + suffix + "." + pathExtension
    }
}
