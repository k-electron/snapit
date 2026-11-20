import AppKit
import ScreenCaptureKit

/// The real source of frozen frames: one ScreenCaptureKit screenshot per display, taken together.
struct ScreenCaptureKitAreaSource: AreaCaptureSource {
    var pointerLocation: CGPoint { NSEvent.mouseLocation }

    func freezeDisplays() async throws -> [FrozenDisplay] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

        var jobs: [Job] = []
        for screen in NSScreen.screens {
            guard
                let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
                let display = content.displays.first(where: { $0.displayID == id })
            else { continue }
            let origin = CGDisplayBounds(id).origin
            jobs.append(Job(filter: ScreenCaptureKitSource.filter(for: display, in: content), frame: screen.frame, cgOrigin: origin))
        }
        guard !jobs.isEmpty else { throw ScreenCaptureError.noDisplay }

        // Every display at once, so the overlay is up as soon as the slowest one is.
        let shots = try await withThrowingTaskGroup(of: (Int, CapturedScreen).self) { group in
            for (index, job) in jobs.enumerated() {
                group.addTask { (index, try await ScreenCaptureKitSource.screenshot(filter: job.filter)) }
            }
            var shots: [Int: CapturedScreen] = [:]
            for try await (index, screen) in group { shots[index] = screen }
            return shots
        }
        return jobs.enumerated().compactMap { index, job in
            shots[index].map { FrozenDisplay(frame: job.frame, cgOrigin: job.cgOrigin, screen: $0) }
        }
    }

    /// A display waiting to be photographed. The filter is only read by the screenshot call.
    private nonisolated struct Job: @unchecked Sendable {
        let filter: SCContentFilter
        let frame: CGRect
        let cgOrigin: CGPoint
    }
}
