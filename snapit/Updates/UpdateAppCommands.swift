import Foundation

nonisolated extension SocketCommand {
    /// `update-script release <tag> <html_url> <notes> [draft|prerelease]`: the next requests are
    /// answered with HTTP 200 and a release object of that tag, link and notes (arguments are
    /// percent-encoded, so notes may hold spaces and lines). The link is only there to be ignored. `update-script raw <status> [<body>]`:
    /// that status and that body, whatever it is. `update-script offline`, `update-script timeout`:
    /// the failures. `update-script hold on|off`: while on, a request waits to be answered, so a run
    /// can see a check in progress. `update-script hold-download <percent>|off`: a download of a
    /// release's file stops once that share of it has arrived (the Update window shows the progress;
    /// the same command with another share moves it) until `off`, or until the Update is cancelled.
    /// `update-script hold-swap on|off`: while on, an Update waits just after the swap has begun
    /// (the work in progress cancelled) and before the bundle is swapped. A release's files (`snapit-X.Y.Z.dmg` and its `.sha256`) are
    /// served from `<root>/update-assets/` while the script is a release or raw answer; offline and
    /// timeout fail them too. Test mode only.
    static let updateScript = SocketCommand("update-script")
    /// How many requests the check has sent (to the fixture endpoint). Test mode only.
    static let updateRequests = SocketCommand("update-requests")
    /// `update-installed-version <x.y.z>|reset`: pretend another bundle version. Test mode only.
    static let updateInstalledVersion = SocketCommand("update-installed-version")
    /// `update-redirect [asset] <url>`: whether the real endpoint would follow a redirect of its
    /// request (of a release file's download, with `asset`) to that address: `follow` or `refuse`.
    /// Test mode only.
    static let updateRedirect = SocketCommand("update-redirect")
    /// `update-compare <a> <b>`: how version `a` compares with `b` through `ReleaseVersion`:
    /// `newer`, `same`, `older`, or `invalid a`, `invalid b`. Test mode only.
    static let updateCompare = SocketCommand("update-compare")
}

extension SocketCommandRegistry {
    /// What the Editor helper's update window asks of the menu bar app: the check, the Update, how
    /// far it has got and ending it.
    func registerUpdateAppCommands() {
        register(.checkForUpdates) { _ in await UpdateCheck.run().wire }
        register(.updateStatus) { _ in UpdateInstall.progress.wire }
        register(.cancelUpdate) { _ in await UpdateInstall.cancel() }
        register(.installUpdate) { request in
            await UpdateInstall.run(announcing: request.arguments.first ?? "")
        }
        guard TestMode.isActive else { return }
        register(.updateScript) { request in Self.script(request.arguments) }
        register(.updateRequests) { _ in String(FixtureReleaseEndpoint.shared.requestCount) }
        register(.updateInstalledVersion) { request in
            guard let value = request.arguments.first else { return "error update-installed-version <x.y.z>|reset" }
            InstalledVersion.pretended = value == "reset" ? nil : value
            return "ok"
        }
        register(.updateRedirect) { request in
            let isAsset = request.arguments.first == "asset"
            guard let text = request.arguments.dropFirst(isAsset ? 1 : 0).first, let url = URL(string: text) else {
                return "error update-redirect [asset] <url>"
            }
            let source = isAsset ? ReleaseRequest.asset(tag: "v1.0.0", name: "snapit-1.0.0.dmg") : ReleaseRequest.latest
            return source?.allowsRedirect(to: url) == true ? "follow" : "refuse"
        }
        register(.updateCompare) { request in
            guard request.arguments.count == 2 else { return "error update-compare <a> <b>" }
            guard let a = ReleaseVersion(request.arguments[0]) else { return "invalid a" }
            guard let b = ReleaseVersion(request.arguments[1]) else { return "invalid b" }
            return a > b ? "newer" : a == b ? "same" : "older"
        }
    }

    private static func script(_ arguments: [String]) -> String {
        let endpoint = FixtureReleaseEndpoint.shared
        switch arguments.first {
        case "release" where arguments.count >= 4:
            var object: [String: Any] = ["tag_name": arguments[1], "html_url": arguments[2], "body": arguments[3]]
            if arguments.count > 4 { object[arguments[4]] = true }
            guard let body = try? JSONSerialization.data(withJSONObject: object) else { return "error not JSON" }
            endpoint.script = .response(status: 200, body: body)
        case "raw" where arguments.count >= 2:
            guard let status = Int(arguments[1]) else { return "error update-script raw <status> [<body>]" }
            endpoint.script = .response(status: status, body: Data((arguments.dropFirst(2).first ?? "").utf8))
        case "offline": endpoint.script = .offline
        case "timeout": endpoint.script = .timeout
        case "hold" where arguments.count == 2 && (arguments[1] == "on" || arguments[1] == "off"):
            endpoint.hold(arguments[1] == "on")
        case "hold-download" where arguments.count == 2:
            if arguments[1] == "off" {
                endpoint.holdDownload(nil)
            } else if let share = Int(arguments[1]), (0...100).contains(share) {
                endpoint.holdDownload(share)
            } else {
                return "error update-script hold-download <percent>|off"
            }
        case "hold-swap" where arguments.count == 2 && (arguments[1] == "on" || arguments[1] == "off"):
            FixtureInstallEnvironment.shared.holdSwap(arguments[1] == "on")
        default:
            return "error update-script release <tag> <html_url> <notes> [draft|prerelease] | raw <status> [<body>] | offline | timeout | hold on|off | hold-download <percent>|off | hold-swap on|off"
        }
        return "ok"
    }
}
