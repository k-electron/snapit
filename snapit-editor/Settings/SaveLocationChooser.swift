import AppKit

/// Choosing the Save location: the folder chooser, and writing the `saveLocation` key. Settings,
/// Onboarding and the folder Permission guide all go through here, so there is one path that
/// changes the Save location.
@MainActor
enum SaveLocationChooser {
    /// Shows the folder chooser (a sheet of `window` when there is one) and calls `chosen` with the
    /// folder the user picks. A scripted run never shows it: it calls `set` directly.
    static func choose(startingAt folder: URL, from window: NSWindow?, chosen: @escaping @MainActor (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = folder
        panel.prompt = "Choose"
        panel.message = "Choose the folder Save writes into"
        let accept: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in chosen(url) }
        }
        if let window { panel.beginSheetModal(for: window, completionHandler: accept) } else { panel.begin(completionHandler: accept) }
    }

    /// Makes `url` the Save location: the next Save writes there.
    static func set(_ url: URL) {
        AppDefaults.store.set(url.path, forKey: GeneralSettings.saveLocationKey)
    }
}
