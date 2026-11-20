/// Which action each Shortcut runs. A feature adds one line here when it adds a Shortcut.
@MainActor
enum ShortcutBindings {
    static func registerAll() {
        Shortcuts.current.register(.area) { await AreaCaptureFlow.start() }
        Shortcuts.current.register(.screen) { await ScreenCaptureFlow.run() }
    }
}
