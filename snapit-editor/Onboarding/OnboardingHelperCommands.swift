import AppKit

nonisolated extension SocketCommand {
    /// Facts about the Onboarding window: `window`, `title`, `activation`, `step`, `step-number`,
    /// `step-title`, `stored-step` (what a relaunch would resume at), `heading`, `text`, `try-it`,
    /// `user-guide` (`available` once the User Guide window has set its hook), the step's own
    /// lines (`save-location`, `shortcut <id>|<combo>|<glyphs>|<flag>`, `login`, and the Permission
    /// guide's `guide-…` lines at the Screen Recording step) and one
    /// `button <id>|<title>|<tooltip>` line per button. Test mode only.
    static let onboardingFacts = SocketCommand("onboarding-facts")
    /// `onboarding-press <button id>`: does what clicking the button does. Test mode only.
    static let onboardingPress = SocketCommand("onboarding-press")
    /// Does what happens when the user comes back to snapit's window (it deactivated, then became
    /// active): the Permission guide looks at Screen Recording again. A scripted run never activates
    /// the helper, so this stands in for it. Test mode only.
    static let onboardingActivate = SocketCommand("onboarding-activate")
    /// `onboarding-hide`, `onboarding-unhide`: take the window off screen and bring it back, as
    /// another app covering it would. Test mode only.
    static let onboardingHide = SocketCommand("onboarding-hide")
    static let onboardingUnhide = SocketCommand("onboarding-unhide")
    /// Presses the window's close button. The helper quits when no other window is open, so a reply
    /// may never come: wait for the process to go. Test mode only.
    static let onboardingClose = SocketCommand("onboarding-close")
    /// `onboarding-key <key code> [<modifier>,...]`: a key press as a Shortcut recorder receives it.
    static let onboardingKey = SocketCommand("onboarding-key")
    /// `onboarding-choose-save-location <folder>`: what choosing a folder in the chooser does (inside
    /// the run's root). Test mode only.
    static let onboardingChooseSaveLocation = SocketCommand("onboarding-choose-save-location")
    /// `onboarding-snapshot <png path>`: renders the window's view into the run's root. Test mode only.
    static let onboardingSnapshot = SocketCommand("onboarding-snapshot")
    /// `onboarding-user-guide-fixture on|off`: sets or clears the User Guide hook with one that
    /// appends a line to `<root>/user-guide-opened`. Test mode only.
    static let onboardingUserGuideFixture = SocketCommand("onboarding-user-guide-fixture")
    /// `system-shortcut-fixture add <key code> [<modifier>,...]` or `reset`: macOS's own shortcuts
    /// that a Shortcut can clash with, besides ⌘⇧3, ⌘⇧4 and ⌘⇧5. Test mode only.
    static let systemShortcutFixture = SocketCommand("system-shortcut-fixture")

    /// The same for a Permission guide that has its own window: `guide-facts` (`window`, `title`,
    /// `activation`, then the guide's lines), `guide-press <button id>`, `guide-activate`,
    /// `guide-hide`, `guide-unhide`, `guide-close`, `guide-snapshot <png path>`. Test mode only.
    static let guideFacts = SocketCommand("guide-facts")
    static let guidePress = SocketCommand("guide-press")
    static let guideActivate = SocketCommand("guide-activate")
    static let guideHide = SocketCommand("guide-hide")
    static let guideUnhide = SocketCommand("guide-unhide")
    static let guideClose = SocketCommand("guide-close")
    static let guideSnapshot = SocketCommand("guide-snapshot")
}

extension SocketCommandRegistry {
    func registerOnboardingHelperCommands() {
        register(.showOnboarding) { _ in
            OnboardingWindow.show()
            // The window is on screen when the reply goes out, not just ordered front.
            CATransaction.flush()
            return "ok"
        }
        register(.showPermissionGuide) { request in
            guard let kind = request.arguments.first.flatMap(PermissionGuideKind.init(rawValue:)) else {
                return "error show-permission-guide screen-recording"
            }
            PermissionGuideWindow.show(kind)
            CATransaction.flush()
            return "ok"
        }
        guard TestMode.isActive else { return }
        registerOnboardingTestCommands()
        registerPermissionGuideTestCommands()
        register(.systemShortcutFixture) { request in
            switch request.arguments.first {
            case "reset":
                FixtureSystemShortcuts.taken = []
                return "ok"
            case "add":
                guard let combo = ShortcutCombo.parse(wire: Array(request.arguments.dropFirst())), let combo else {
                    return "error system-shortcut-fixture add <key code> [<modifier>,...]"
                }
                FixtureSystemShortcuts.taken += [ShortcutCombo.wire(combo)]
                return "ok"
            default:
                return "error system-shortcut-fixture add <key code> [<modifier>,...] | reset"
            }
        }
    }

    private func registerOnboardingTestCommands() {
        register(.onboardingFacts) { _ in OnboardingFacts.describe() }
        register(.onboardingPress) { request in
            guard let onboarding = OnboardingWindow.shared, let id = request.arguments.first else {
                return "error no Onboarding window"
            }
            // The chooser is a real panel: a scripted run sets the folder with its own command.
            guard id != onboarding.model.chooseSaveLocationButton.id else {
                return "error use onboarding-choose-save-location <folder>"
            }
            return await onboarding.model.press(id) ? "ok" : "error no button \(id)"
        }
        register(.onboardingActivate) { _ in
            guard let onboarding = OnboardingWindow.shared else { return "error no Onboarding window" }
            onboarding.model.windowResigned()
            await onboarding.model.windowBecameActive()
            return "ok"
        }
        register(.onboardingHide) { _ in WindowTesting.hide(OnboardingWindow.shared?.window) }
        register(.onboardingUnhide) { _ in WindowTesting.unhide(OnboardingWindow.shared?.window) }
        register(.onboardingClose) { _ in WindowTesting.close(OnboardingWindow.shared?.window) }
        register(.onboardingSnapshot) { request in WindowTesting.snapshot(OnboardingWindow.shared?.window, request.arguments) }
        register(.onboardingKey) { request in
            guard let onboarding = OnboardingWindow.shared, let window = onboarding.window else {
                return "error no Onboarding window"
            }
            return await RecorderKeyEvent.send(request.arguments, to: window, model: onboarding.model.settings)
        }
        register(.onboardingChooseSaveLocation) { request in
            guard let onboarding = OnboardingWindow.shared, let path = request.arguments.first else {
                return "error no Onboarding window"
            }
            guard WindowTesting.isInsideRoot(path) else { return "error folder must be inside the test root" }
            onboarding.model.settings.setSaveLocation(URL(fileURLWithPath: path, isDirectory: true))
            return "ok"
        }
        register(.onboardingUserGuideFixture) { request in
            switch request.arguments.first {
            case "on":
                UserGuideLink.open = {
                    if let root = TestMode.root {
                        FixtureScreenRecording.append("opened\n", to: root.appendingPathComponent("user-guide-opened"))
                    }
                }
            case "off":
                UserGuideLink.open = nil
            default:
                return "error onboarding-user-guide-fixture on|off"
            }
            return "ok"
        }
    }

    private func registerPermissionGuideTestCommands() {
        register(.guideFacts) { _ in
            guard let guide = PermissionGuideWindow.shared, let window = guide.window else { return "window=none" }
            return (WindowTesting.facts(window) + guide.model.facts()).joined(separator: "\n")
        }
        register(.guidePress) { request in
            guard let guide = PermissionGuideWindow.shared, let id = request.arguments.first else { return "error no guide window" }
            return await guide.model.press(id) ? "ok" : "error no button \(id)"
        }
        register(.guideActivate) { _ in
            guard let guide = PermissionGuideWindow.shared else { return "error no guide window" }
            guide.model.windowResigned()
            await guide.model.windowBecameActive()
            return "ok"
        }
        register(.guideHide) { _ in WindowTesting.hide(PermissionGuideWindow.shared?.window) }
        register(.guideUnhide) { _ in WindowTesting.unhide(PermissionGuideWindow.shared?.window) }
        register(.guideClose) { _ in WindowTesting.close(PermissionGuideWindow.shared?.window) }
        register(.guideSnapshot) { request in WindowTesting.snapshot(PermissionGuideWindow.shared?.window, request.arguments) }
    }
}

/// What a scripted run does to a helper window of Onboarding or a Permission guide.
@MainActor
enum WindowTesting {
    static func facts(_ window: NSWindow) -> [String] {
        [
            "window=\(window.isVisible ? "visible" : "hidden")",
            "title=\(window.title)",
            "activation=\(NSApp.activationPolicy() == .regular ? "regular" : "accessory")",
        ]
    }

    static func hide(_ window: NSWindow?) -> String {
        guard let window else { return "error no window" }
        window.orderOut(nil)
        return "ok"
    }

    static func unhide(_ window: NSWindow?) -> String {
        guard let window else { return "error no window" }
        window.makeKeyAndOrderFront(nil)
        return "ok"
    }

    static func close(_ window: NSWindow?) -> String {
        guard let window else { return "error no window" }
        window.performClose(nil)
        return "ok"
    }

    static func isInsideRoot(_ path: String) -> Bool {
        guard let root = TestMode.root?.standardizedFileURL.path else { return false }
        return URL(fileURLWithPath: path).standardizedFileURL.path.hasPrefix(root + "/")
    }

    static func snapshot(_ window: NSWindow?, _ arguments: [String]) -> String {
        guard let window, let view = window.contentView, let path = arguments.first, isInsideRoot(path),
            let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        else { return "error snapshot <png path inside the test root>" }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { return "error no png" }
        do {
            try png.write(to: URL(fileURLWithPath: path))
            return "ok"
        } catch {
            return "error \(error)"
        }
    }
}

/// What the scripted run reads of the Onboarding window.
@MainActor
enum OnboardingFacts {
    static func describe() -> String {
        guard let onboarding = OnboardingWindow.shared, let window = onboarding.window else { return "window=none" }
        let model = onboarding.model
        let stored: String
        switch OnboardingProgress.stored {
        case .finished: stored = OnboardingProgress.finishedValue
        case .step(let step): stored = step.rawValue
        }
        var lines = WindowTesting.facts(window)
        lines += [
            "step=\(model.step.rawValue)",
            "step-number=\(model.step.number)",
            "step-title=\(model.step.title)",
            "stored-step=\(stored)",
            "heading=\(model.heading)",
            "text=\(model.text)",
            "try-it=\(model.tryIt)",
            "user-guide=\(UserGuideLink.open == nil ? "unavailable" : "available")",
        ]
        let settings = model.settings
        switch model.step {
        case .saveLocation:
            lines.append("save-location=\(settings.saveLocation.path)")
        case .shortcuts:
            for entry in ShortcutCatalog.entries {
                let combo = settings.combo(for: entry)
                let value = settings.shortcutsLoaded ? ShortcutCombo.wire(combo) : "unknown"
                let recording = settings.recordingID == entry.shortcut.id
                lines.append(
                    "shortcut \(entry.shortcut.id)|\(recording ? "recording" : value)|\(combo?.displayString ?? "")|"
                        + "\(settings.note(for: entry) ?? "")")
            }
        case .openAtLogin:
            lines.append("login=\(SettingsFacts.loginValue(settings.login))")
        default:
            break
        }
        lines += model.navigation.map { "button \($0.id)|\($0.title)|\($0.tooltip)" }
        if model.step == .screenRecording {
            lines += model.guide.facts()
        } else {
            lines += model.stepButtons.map { "button \($0.id)|\($0.title)|\($0.tooltip)" }
        }
        return lines.joined(separator: "\n")
    }
}
