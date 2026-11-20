import Foundation

/// How long the last Capture took to reach the Editor: from the moment its pixels were ready to
/// the Editor window showing. Recorded once per Capture; read by the scripted run through
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
