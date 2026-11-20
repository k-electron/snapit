import AppKit
import ScreenCaptureKit

/// The real fresh Capture: one ScreenCaptureKit screenshot of the display, taken now, with all of
/// snapit's windows excluded by excluding its application (`OwnWindowExclusion`), so a window that
/// appeared after the list was fetched is out too.
struct ScreenCaptureKitTimedSource: TimedCaptureSource {
    func captureFresh(_ request: FreshCaptureRequest, hideOwnWindows: @MainActor () -> Void) async throws
        -> CapturedScreen
    {
        var content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        var plan = Self.plan(for: content)
        if plan == .hideWindows {
            // The system has not listed snapit, so no filter can name it: take its windows off
            // screen and give the compositor a moment, so they cannot be in the Capture.
            hideOwnWindows()
            try await Task.sleep(for: .milliseconds(200))
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            plan = Self.plan(for: content)
        }
        guard let display = content.displays.first(where: { $0.displayID == request.displayID }) else {
            throw ScreenCaptureError.noDisplay
        }
        let filter: SCContentFilter
        if case .application(let excepting) = plan, let own = Self.ownApplication(in: content) {
            let kept = content.windows.filter { excepting.contains(Int($0.windowID)) }
            filter = SCContentFilter(display: display, excludingApplications: [own], exceptingWindows: kept)
        } else {
            // Still not listed: the windows are off screen; leave out any that are still listed.
            filter = ScreenCaptureKitSource.filter(for: display, in: content)
        }
        return try await ScreenCaptureKitSource.capture(filter: filter)
    }

    private static func ownApplication(in content: SCShareableContent) -> SCRunningApplication? {
        content.applications.first { $0.bundleIdentifier == AppIdentity.mainBundleIdentifier }
    }

    private static func plan(for content: SCShareableContent) -> OwnWindowExclusion {
        let own = content.windows.filter { $0.owningApplication?.bundleIdentifier == AppIdentity.mainBundleIdentifier }
        return OwnWindowExclusion.plan(
            applicationListed: ownApplication(in: content) != nil,
            ownWindows: own.map { OwnWindowExclusion.Window(number: Int($0.windowID), layer: $0.windowLayer) })
    }
}
