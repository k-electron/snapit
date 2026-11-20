import Observation

/// Whether there is a Last Capture, and which Capture it is. Observable, so the menu's
/// "Reopen Last Capture" item is enabled exactly while one exists (`LastCaptureMenu`).
///
/// `CaptureHandoff` keeps it current: a Capture that opens in the Editor becomes the Last Capture,
/// Delete Capture, a damaged store and quitting clear it.
@MainActor
@Observable
final class LastCapture {
    static let shared = LastCapture()

    /// The Last Capture's number (`CaptureFiles.url(number:)` is its pixel file); nil when there is none.
    private(set) var number: Int?

    var exists: Bool { number != nil }

    func set(_ number: Int?) {
        if self.number != number { self.number = number }
    }
}
