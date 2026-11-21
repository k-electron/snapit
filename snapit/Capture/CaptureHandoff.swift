import Foundation

/// Hands a Capture to the Editor: the pixels go into a Capture file (memory-mapped, never over
/// the socket), then the Editor helper is told to open Capture N.
///
/// Only the newest Capture's files are kept (it becomes the Last Capture, see `LastCapture`):
/// once Capture N is open in the Editor, the one before it goes. A Capture that fails to open
/// leaves the previous one alone. Deleting the Capture, or quitting, removes the files too. The
/// menu bar app holds no pixels afterwards: the mapping is gone when `publish` returns.
@MainActor
enum CaptureHandoff {
    /// Starts at a number no earlier run of the menu bar app used (milliseconds since 1970), so a
    /// helper that outlived a crashed menu bar app never mistakes a new Capture for one of its own.
    private static var nextNumber = Int(Date().timeIntervalSince1970 * 1000)
    private static var latestNumber: Int?
    /// Test mode only: the frame being written for the latest Capture, held weakly, and whether it
    /// was already gone when the Editor was asked to open that Capture (`nil` until then).
    private static weak var frameForTest: AnyObject?
    private(set) static var frameFreedAtOpen: Bool?
    /// Test mode only: the latest frame carried no lifetime probe, so nothing can be said about it.
    private(set) static var frameProbeMissing = false

    /// Writes `screen` as the next Capture's file and returns its number. Call `didOpen` once
    /// the Editor has it, or `discard` when it could not be opened.
    static func publish(_ screen: CapturedScreen) async throws -> Int {
        trackFrameForTest(screen)
        let number = nextNumber
        nextNumber += 1
        try await write(number: number, screen: screen)
        return number
    }

    /// Writes the pixel rectangle `area` of a frozen display's `screen` (an Area Capture) as the
    /// next Capture's file: the engine crops it straight into the file.
    static func publish(_ screen: CapturedScreen, cropping area: PixelRect) async throws -> Int {
        trackFrameForTest(screen)
        let number = nextNumber
        nextNumber += 1
        try await write(number: number, screen: screen, area: area)
        return number
    }

    private static func trackFrameForTest(_ screen: CapturedScreen) {
        guard TestMode.isActive else { return }
        frameForTest = screen.lifetimeProbe
        frameProbeMissing = screen.lifetimeProbe == nil
        frameFreedAtOpen = nil
    }

    /// The Editor is about to be asked to open a Capture that was just written (test mode only).
    static func noteOpenForTest() {
        guard TestMode.isActive, frameFreedAtOpen == nil else { return }
        frameFreedAtOpen = frameForTest == nil
    }

    /// Capture N is open in the Editor: it is now the Last Capture, and the one before goes.
    static func didOpen(number: Int) {
        // The helper has stopped writing the previous Last Capture's state before it answered
        // `open-capture` (a new Capture supersedes it first), so nothing recreates its files.
        if let previous = latestNumber, previous != number { CaptureFiles.remove(number: previous) }
        latestNumber = number
        LastCapture.shared.set(number)
    }

    /// Capture N could not be opened: its file goes, the previous Capture stays.
    static func discard(number: Int) {
        CaptureFiles.remove(number: number)
    }

    /// The user deleted Capture N in the Editor, or the store of Capture N is damaged and
    /// cannot be reopened.
    static func delete(number: Int) {
        CaptureFiles.remove(number: number)
        if latestNumber == number {
            latestNumber = nil
            LastCapture.shared.set(nil)
        }
    }

    /// Removes every Capture file: at launch (anything left by a crash) and at quit.
    static func removeAll() {
        CaptureFiles.removeAll()
        latestNumber = nil
        LastCapture.shared.set(nil)
    }

    @concurrent
    private static func write(number: Int, screen: CapturedScreen) async throws {
        try CaptureFiles.write(number: number, image: screen.image, scale: screen.scale)
    }

    @concurrent
    private static func write(number: Int, screen: CapturedScreen, area: PixelRect) async throws {
        try CaptureFiles.write(number: number, image: screen.image, cropping: area, scale: screen.scale)
    }
}
