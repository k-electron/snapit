/// Which action each Shortcut runs. A feature adds one line here when it adds a Shortcut. Every
/// action runs through `OnboardingLauncher.whenSetUp`: until Onboarding is finished a Shortcut
/// opens Onboarding instead.
@MainActor
enum ShortcutBindings {
    static func registerAll() {
        Shortcuts.current.register(.area) {
            // The Area Shortcut cancels a Timed Capture's countdown, which only a finished Onboarding has started.
            if AreaCaptureFlow.countdown != nil {
                await AreaCaptureFlow.start()
                return
            }
            await OnboardingLauncher.whenSetUp { await AreaCaptureFlow.start() }
        }
        Shortcuts.current.register(.window) { await OnboardingLauncher.whenSetUp { await WindowCaptureFlow.start() } }
        Shortcuts.current.register(.screen) { await OnboardingLauncher.whenSetUp { await ScreenCaptureFlow.run() } }
        Shortcuts.current.register(.pickColor) {
            await OnboardingLauncher.whenSetUp { await AreaCaptureFlow.start(mode: .pickColor) }
        }
    }
}
