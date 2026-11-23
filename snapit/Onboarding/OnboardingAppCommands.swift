import Foundation

nonisolated extension SocketCommand {
    /// `screen-recording-simulate notDetermined|denied|turnedOff|revoked|granted|grantedStale`: puts the fake
    /// macOS where the user doing it would (`turnedOff`: it was granted to this build and the user
    /// switched it off; `grantedStale`: it was granted to another build; `revoked`: only the grant goes,
    /// what snapit remembers stays). Test mode only.
    static let screenRecordingSimulate = SocketCommand("screen-recording-simulate")
    /// `screen-recording-build <id>`: makes this copy another build to the fake macOS, as an update
    /// does. Test mode only.
    static let screenRecordingBuild = SocketCommand("screen-recording-build")
    /// `state=<state>`, `requests=<n>` (times snapit asked macOS) and `resets=<n>` (times it reset
    /// its own entry), one per line. Test mode only.
    static let screenRecordingFacts = SocketCommand("screen-recording-facts")
    /// `tcc-reset-fail on|off`: makes the fixture reset fail, as `tccutil` can. Test mode only.
    static let tccResetFail = SocketCommand("tcc-reset-fail")
    /// Runs what a launch does for Onboarding and the update's Permission guide; replies
    /// `onboarding`, `permission-guide` or `none`. Test mode only.
    static let onboardingLaunchCheck = SocketCommand("onboarding-launch-check")
}

extension SocketCommandRegistry {
    /// What the helper's Onboarding and Permission guide ask of the menu bar app.
    func registerOnboardingAppCommands() {
        register(.screenRecordingState) { _ in ScreenRecordingAsk.stateReply() }
        register(.screenRecordingRequest) { _ in await ScreenRecordingAsk.run().reply }
        register(.relaunchSnapit) { _ in await SnapitRelaunch.run() }
        guard TestMode.isActive else { return }
        register(.onboardingLaunchCheck) { _ in await OnboardingLauncher.runAtLaunch().rawValue }
        register(.screenRecordingSimulate) { request in
            let defaults = AppDefaults.store
            let build = FixtureScreenRecording.buildID()
            switch request.arguments.first {
            case "granted":
                FixtureScreenRecording.setGranted(true)
            case "notDetermined":
                FixtureScreenRecording.setGranted(false)
                ScreenRecordingPermission.current.forgetHistory()
            case "denied":
                FixtureScreenRecording.setGranted(false)
                ScreenRecordingPermission.current.forgetHistory()
                defaults.set(true, forKey: DerivedPermission.requestedKey)
            case "revoked":
                FixtureScreenRecording.setGranted(false)
            case "turnedOff":
                FixtureScreenRecording.setGranted(false)
                defaults.set(true, forKey: DerivedPermission.grantedBeforeKey)
                defaults.set(build, forKey: DerivedPermission.grantedBuildKey)
                defaults.removeObject(forKey: DerivedPermission.requestedKey)
            case "grantedStale":
                FixtureScreenRecording.setGranted(false)
                defaults.set(true, forKey: DerivedPermission.grantedBeforeKey)
                defaults.set("previous-" + build, forKey: DerivedPermission.grantedBuildKey)
                defaults.removeObject(forKey: DerivedPermission.requestedKey)
            default:
                return "error screen-recording-simulate notDetermined|denied|turnedOff|revoked|granted|grantedStale"
            }
            return "ok"
        }
        register(.screenRecordingBuild) { request in
            guard let id = request.arguments.first else { return "error screen-recording-build <id>" }
            FixtureScreenRecording.setBuildID(id)
            return "ok"
        }
        register(.screenRecordingFacts) { _ in
            [
                "state=\(ScreenRecordingPermission.current.state.rawValue)",
                "requests=\(FixtureScreenRecording.lineCount(FixtureScreenRecording.requestsLog))",
                "resets=\(FixtureScreenRecording.lineCount(FixtureScreenRecordingReset.log))",
            ].joined(separator: "\n")
        }
        register(.tccResetFail) { request in
            guard let marker = FixtureScreenRecordingReset.failureMarker, let value = request.arguments.first,
                value == "on" || value == "off"
            else { return "error tcc-reset-fail on|off" }
            if value == "on" {
                FileManager.default.createFile(atPath: marker.path, contents: nil)
            } else {
                try? FileManager.default.removeItem(at: marker)
            }
            return "ok"
        }
    }
}

/// "Relaunch snapit": the menu bar app starts a new copy of itself and quits. Screen Recording
/// is granted to the menu bar app, and macOS only lets a process use it from its next launch on.
///
/// An Update relaunches through it too, starting the newer copy it swapped in at `appURL`. That
/// relaunch hands the Last Capture and the Update's staging folder to the new copy
/// (`UpdateHandoff`); any other relaunch quits as snapit always does, and the Last Capture goes.
@MainActor
enum SnapitRelaunch {
    static func run(appAt appURL: URL = Bundle.main.bundleURL, updateStagingFolder: URL? = nil) async -> String {
        // The Editor helper goes first, so the relaunched copy starts a helper of its own (it shows
        // Onboarding again at the step it was on) instead of meeting this one on its way out. Its `quit`
        // runs `QuitPreparation`. The question about Editors with unexported edits is asked by the
        // Permission guide in the helper before it sends `relaunch-snapit`, so by now the user agreed.
        if updateStagingFolder != nil, await CommandSocketClient.isListening(at: AppIdentity.editorSocketPath) {
            // The Last Capture goes with the Update: what was drawn a moment ago is written first.
            _ = try? await CommandSocketClient.send(.saveLastCapture, to: AppIdentity.editorSocketPath, timeoutSeconds: 5)
        }
        await HelperWindowLauncher.quitRunningHelper()
        SocketOwnership.release()
        let handoff = updateStagingFolder.map {
            UpdateHandoff(oldProcessID: getpid(), stagingFolder: $0, lastCapture: LastCapture.shared.number)
        }
        CaptureHandoff.isHandedToUpdate = handoff != nil
        do {
            try await InstallRelaunch.start(appAt: appURL, arguments: handoff?.arguments ?? [])
        } catch {
            CaptureHandoff.isHandedToUpdate = false
            SocketOwnership.reacquire()
            return "error snapit could not relaunch: \(error.localizedDescription)"
        }
        InstallRelaunch.quitSoon()
        return "ok"
    }
}
