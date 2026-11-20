import Foundation

/// The six steps of Onboarding, in order.
enum OnboardingStep: String, CaseIterable {
    case welcome
    case screenRecording
    case saveLocation
    case shortcuts
    case openAtLogin
    case done

    /// 1 for Welcome … 6 for Done.
    var number: Int { (Self.allCases.firstIndex(of: self) ?? 0) + 1 }

    /// What the step is called (in the Back and Continue tooltips).
    var title: String {
        switch self {
        case .welcome: "Welcome"
        case .screenRecording: "Screen Recording"
        case .saveLocation: "Save location"
        case .shortcuts: "Shortcuts"
        case .openAtLogin: "Open at Login"
        case .done: "Done"
        }
    }

    /// The step's heading in the window.
    var heading: String {
        switch self {
        case .welcome: "Welcome to snapit"
        case .done: "You're all set"
        default: title
        }
    }

    var next: OnboardingStep? { number < Self.allCases.count ? Self.allCases[number] : nil }

    var previous: OnboardingStep? { number > 1 ? Self.allCases[number - 2] : nil }
}

/// How far Onboarding has got, kept through `AppDefaults.store` so either process reads it and
/// it survives a relaunch.
///
/// The stored value is the step to resume at, or `finished`. Reaching the Done step finishes
/// Onboarding (its own "Try it: press ⌃⌥⌘4" must start a Capture, not open Onboarding again).
enum OnboardingProgress {
    static let key = "onboardingStep"
    static let finishedValue = "finished"

    enum Stored: Equatable {
        case step(OnboardingStep)
        case finished
    }

    /// Where Onboarding stands. A copy that never stored anything starts at Welcome. Test mode
    /// starts finished, so no other flow of the scripted run meets Onboarding; a flow that tests it
    /// stores a step first.
    static var stored: Stored {
        guard let text = AppDefaults.store.string(forKey: key), !text.isEmpty else {
            return TestMode.isActive ? .finished : .step(.welcome)
        }
        if text == finishedValue { return .finished }
        if let step = OnboardingStep(rawValue: text), step != .done { return .step(step) }
        return .step(.welcome)
    }

    static var isFinished: Bool { stored == .finished }

    /// The step to open at: the stored one, Welcome when Onboarding is already finished.
    static var resumeStep: OnboardingStep {
        if case .step(let step) = stored { return step }
        return .welcome
    }

    /// Records that `step` is the one showing now.
    static func store(_ step: OnboardingStep) {
        AppDefaults.store.set(step == .done ? finishedValue : step.rawValue, forKey: key)
    }
}
