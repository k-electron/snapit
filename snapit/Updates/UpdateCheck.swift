import Foundation

/// Check for Updates, in the menu bar app: one request to GitHub, made only when the user clicks
/// Check for Updates… (the menu, or Settings › About through the Editor helper). There is no
/// timer, no check at launch and no background checking. A click while a check is running joins
/// it: one click, one request.
@MainActor
enum UpdateCheck {
    private static var running: Task<UpdateAnswer, Never>?
    /// The release the latest check announced as newer; nil when it found none. An Update installs
    /// this one.
    private(set) static var announced: AnnouncedRelease?

    static func run() async -> UpdateAnswer {
        if let running { return await running.value }
        let task = Task { @MainActor in
            let installed = InstalledVersion.string
            let result: Result<ReleaseResponse, ReleaseEndpointError>
            do {
                result = .success(try await ReleaseEndpoints.current.fetch(.latest))
            } catch let error as ReleaseEndpointError {
                result = .failure(error)
            } catch {
                result = .failure(.offline)
            }
            let decision = UpdateAnswers.decide(for: result, installed: installed)
            announced = decision.announced
            return decision.answer
        }
        running = task
        let answer = await task.value
        running = nil
        return answer
    }
}

/// Asks the Editor helper to show the update window and check (starting the helper when it is not
/// running). The menu bar app never opens a window itself.
@MainActor
enum UpdateWindowLauncher {
    static func show() async {
        do {
            try await EditorHelperLauncher.ensureRunning(activates: EditorActivation.current.activateAtLaunch)
            let reply = try await CommandSocketClient.send(
                .showUpdateCheck, to: AppIdentity.editorSocketPath, timeoutSeconds: 10)
            guard reply == "ok" else { throw EditorHelperError.refused(reply) }
            await EditorHelperLauncher.bringForward()
        } catch {
            NSLog("snapit: could not show the update window: \(error)")
        }
    }
}
