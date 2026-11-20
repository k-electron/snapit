import Foundation

/// How long the last Capture took to reach the Editor, from the moment its pixels were ready (the
/// Capture itself is not counted) to the Editor window being on screen. It covers writing the
/// Capture file, the command to the helper, attaching the Capture to the Editor, showing the window
/// and the helper's replying after it flushed its drawing. In a normal run it also covers asking
/// macOS to bring the helper forward. Recorded once per Capture; read by the scripted run through
/// `capture-timing`.
@MainActor
enum CaptureTiming {
    struct Sample {
        let milliseconds: Double
        /// True when the helper had an Editor built ahead of the Capture.
        let wasWarm: Bool
    }

    private(set) static var last: Sample?

    /// The clock for one Capture, started when its pixels are ready.
    struct Clock {
        private let started = ContinuousClock.now
        private let wasWarm = EditorWarmUp.isWarm

        func stop() {
            let elapsed = ContinuousClock.now - started
            let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
            CaptureTiming.last = Sample(milliseconds: seconds * 1000, wasWarm: wasWarm)
        }
    }
}
