import Foundation

/// Clears snapit's own Screen Recording entry in macOS, which an update leaves behind: each
/// ad-hoc build is a new code identity, so the entry no longer matches and its switch does
/// nothing. Always go through `ScreenRecordingResets.current`; a scripted run swaps in a fixture
/// and never runs the real `tccutil` or touches the real TCC database.
protocol ScreenRecordingReset: Sendable {
    func reset() async throws
}

struct ScreenRecordingResetError: Error, CustomStringConvertible {
    let description: String
}

enum ScreenRecordingResets {
    static let current: any ScreenRecordingReset = TestMode.isActive ? FixtureScreenRecordingReset() : TccutilReset()
}

/// `tccutil reset ScreenCapture <bundle id>`, run from inside the app. The reset was only ever
/// verified from Terminal, so every way it can fail (no tccutil, it cannot run, it exits with an
/// error) is reported, never assumed to have worked. `docs/manual-checks.md` has the real-install check.
struct TccutilReset: ScreenRecordingReset {
    func reset() async throws {
        try await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            process.arguments = ["reset", "ScreenCapture", AppIdentity.mainBundleIdentifier]
            let errors = Pipe()
            process.standardError = errors
            process.standardOutput = FileHandle.nullDevice
            do {
                try process.run()
            } catch {
                throw ScreenRecordingResetError(description: "tccutil could not run: \(error.localizedDescription)")
            }
            // A tccutil that hangs is ended after a few seconds, and reported like any other failure.
            let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
            DispatchQueue.global().asyncAfter(deadline: .now() + 5, execute: watchdog)
            let message = errors.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            watchdog.cancel()
            guard process.terminationReason == .exit else {
                throw ScreenRecordingResetError(description: "tccutil did not finish in time")
            }
            guard process.terminationStatus == 0 else {
                let text = String(decoding: message, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                throw ScreenRecordingResetError(
                    description: "tccutil exited with status \(process.terminationStatus)" + (text.isEmpty ? "" : ": \(text)"))
            }
        }.value
    }
}

/// Test mode's reset: a line in `<root>/tcc-resets` instead of `tccutil`, and macOS no longer
/// granting snapit afterwards, as a real reset leaves it. It fails while `<root>/tcc-reset-fail` exists.
struct FixtureScreenRecordingReset: ScreenRecordingReset {
    static var log: URL? { TestMode.root?.appendingPathComponent("tcc-resets") }
    static var failureMarker: URL? { TestMode.root?.appendingPathComponent("tcc-reset-fail") }

    func reset() async throws {
        if let marker = Self.failureMarker, FileManager.default.fileExists(atPath: marker.path) {
            throw ScreenRecordingResetError(description: "tccutil exited with status 1: the fixture reset fails")
        }
        if let log = Self.log { FixtureScreenRecording.append("reset ScreenCapture \(AppIdentity.mainBundleIdentifier)\n", to: log) }
        FixtureScreenRecording.setGranted(false)
    }
}
