import SwiftUI

/// snapit's menu bar app: an agent (no Dock icon) that lives only in the menu bar.
@main
struct SnapitApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("snapit", systemImage: "camera.viewfinder") {
            MenuBarContent()
        }
        .menuBarExtraStyle(.menu)
    }
}
