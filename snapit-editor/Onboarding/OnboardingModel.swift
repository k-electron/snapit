import AppKit
import Observation

/// What Onboarding shows and does: which of its six steps is on screen, what each step offers, and
/// the models of the pieces it reuses (Settings' model for the Save location, the Shortcut
/// recorders and Open at Login; the Permission guide for Screen Recording).
///
/// The step is stored as soon as it changes (`OnboardingProgress`), so closing the window at any
/// step resumes there. Reaching Done finishes Onboarding.
@MainActor
@Observable
final class OnboardingModel {
    private(set) var step: OnboardingStep
    let settings = SettingsModel()
    let guide = PermissionGuideModel(kind: .screenRecording)

    /// Closes the window (set by the window).
    @ObservationIgnored var closeWindow: () -> Void = {}

    init(step: OnboardingStep) {
        self.step = step
        enter(step)
    }

    // MARK: Moving between steps

    func go(to newStep: OnboardingStep) {
        guard newStep != step else { return }
        settings.cancelRecording()
        step = newStep
        enter(newStep)
    }

    func next() { if let next = step.next { go(to: next) } }
    func back() { if let previous = step.previous { go(to: previous) } }

    /// Stores the step, and does what the step needs when it appears. Each of these looks at the
    /// other process once, when its step shows: nothing polls.
    private func enter(_ step: OnboardingStep) {
        OnboardingProgress.store(step)
        guide.isShown = step == .screenRecording
        switch step {
        case .screenRecording:
            Task { await guide.windowBecameActive() }
        case .shortcuts, .done:
            Task { await settings.refreshShortcuts() }
        case .openAtLogin:
            Task { await settings.refreshLogin() }
        case .welcome, .saveLocation:
            break
        }
    }

    /// The window became active: where Screen Recording stands may have changed while the user was in
    /// System Settings or macOS's prompt, so the Permission guide looks again.
    func windowBecameActive() async {
        guard step == .screenRecording else { return }
        await guide.windowBecameActive()
    }

    func windowResigned() {
        guide.windowResigned()
        settings.cancelRecording()
    }

    // MARK: Words

    var tryIt: String {
        let area = ShortcutCatalog.entries.first { $0.shortcut.id == AppShortcut.area.id }
        let combo = settings.shortcutsLoaded ? area.flatMap { settings.combo(for: $0) } : AppShortcut.area.defaultCombo
        guard let combo else { return "Try it: choose Capture Area in the snapit menu" }
        return "Try it: press \(combo.displayString)"
    }

    var heading: String { step.title }

    var text: String {
        switch step {
        case .welcome:
            "snapit lives in your menu bar, up here. Its menu takes a Capture, reopens the Last Capture and opens Settings. It costs nothing while you are not using it."
        case .screenRecording:
            ""
        case .saveLocation:
            "A saved Capture is written into this folder, with no dialog. Downloads is the default."
        case .shortcuts:
            "Press a Shortcut anywhere to start a Capture. Click one to record another key combination. A flag means macOS uses those keys too."
        case .openAtLogin:
            "Open at Login starts snapit when you log in, so it is always there. It is on by default."
        case .done:
            "snapit is ready. Your Captures open in the Editor straight away."
        }
    }

    // MARK: Buttons

    let doneButton = HelperButton(id: "done", title: "Done", tooltip: "Close Onboarding")
    let chooseSaveLocationButton = HelperButton(
        id: "choose-save-location", title: "Choose…", tooltip: "Choose the folder Save writes into")
    let screenshotShortcutsButton = HelperButton(
        id: "open-screenshot-shortcuts", title: "Open Keyboard Shortcuts in System Settings…",
        tooltip: "Open System Settings, then Keyboard Shortcuts… › Screenshots, to free ⌘⇧3, ⌘⇧4 and ⌘⇧5")
    let userGuideButton = HelperButton(id: "user-guide", title: "Open the User Guide", tooltip: "Open the User Guide")
    let openAtLoginSwitch = HelperButton(id: "open-at-login", title: "Open at Login", tooltip: "Start snapit when you log in")

    var navigation: [HelperButton] {
        var buttons: [HelperButton] = []
        if let previous = step.previous {
            buttons.append(HelperButton(id: "back", title: "Back", tooltip: "Go back to \(previous.title)"))
        }
        if let next = step.next {
            buttons.append(HelperButton(id: "next", title: "Continue", tooltip: "Go on to \(next.title)"))
        } else {
            buttons.append(doneButton)
        }
        return buttons
    }

    /// The buttons of the step itself, besides the navigation.
    var stepButtons: [HelperButton] {
        switch step {
        case .welcome: []
        case .screenRecording: guide.buttons
        case .saveLocation: [chooseSaveLocationButton]
        case .shortcuts: [screenshotShortcutsButton]
        case .openAtLogin: [openAtLoginSwitch]
        case .done: UserGuideLink.open == nil ? [] : [userGuideButton]
        }
    }

    /// Does what the button with this id does. Returns whether there is such a button.
    func press(_ id: String) async -> Bool {
        switch id {
        case "back": back()
        case "next": next()
        case doneButton.id: closeWindow()
        case chooseSaveLocationButton.id: settings.chooseSaveLocation(from: NSApp.keyWindow)
        case screenshotShortcutsButton.id: settings.openScreenshotShortcuts()
        case openAtLoginSwitch.id: await settings.setOpenAtLogin(settings.login != .on)
        case userGuideButton.id: UserGuideLink.open?()
        default:
            guard step == .screenRecording else { return false }
            return await guide.press(id)
        }
        return true
    }
}
