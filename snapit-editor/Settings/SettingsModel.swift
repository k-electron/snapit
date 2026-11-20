import AppKit
import Observation

/// What Settings shows and changes. Every change is written through `AppDefaults.store` at
/// once, and the readers (the Editor, the Area flow, Save) read the key when they need it, so
/// nothing waits for a relaunch. Open at Login and the Shortcuts live in the menu bar app: the
/// model asks it over the socket.
///
/// The window, the Settings menu items and the scripted run's commands all use this one model.
@MainActor
@Observable
final class SettingsModel {
    /// Where Open at Login stands. Read from the menu bar app when Settings opens, never polled.
    enum LoginState: Equatable {
        case unknown
        case on
        case off
        case needsApproval
        case failed(String)
    }

    private(set) var login = LoginState.unknown
    private(set) var saveLocation = SaveLocation.folder
    private(set) var afterSelectingArea = CapturingSettings.afterSelectingArea
    private(set) var closeAfterCopy = EditorSettings.closeAfterCopy
    private(set) var closeAfterSave = EditorSettings.closeAfterSave
    private(set) var standardResolution = ExportSettings.standardResolution
    private(set) var combos: [String: ShortcutCombo?] = [:]
    /// The Shortcut being recorded (its id), if any.
    private(set) var recordingID: String?
    private(set) var shortcutError: String?
    /// The menu bar app being told about the latest recorded Shortcut.
    @ObservationIgnored private(set) var applying: Task<Void, Never>?

    @ObservationIgnored private let recorder = ShortcutRecorder()

    init() {
        for entry in ShortcutCatalog.entries {
            combos[entry.shortcut.id] = ShortcutSettings.combo(for: entry.shortcut)
        }
    }

    /// The version line of About: the version snapit has in its bundle.
    var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = info?["CFBundleVersion"] as? String
        return build.map { "\(version) (\($0))" } ?? version
    }

    /// The engine's version, read through the C ABI.
    var engineVersionText: String { (try? Engine.version()) ?? "unavailable" }

    // MARK: Open at Login

    /// Asks the menu bar app for the status. Called when Settings opens or is brought forward.
    func refreshLogin() async {
        do {
            let reply = try await CommandSocketClient.send(.loginItemStatus, to: AppIdentity.appSocketPath)
            login = Self.loginState(for: reply)
        } catch {
            login = .failed("snapit did not answer. Quit snapit and open it again.")
        }
    }

    func setOpenAtLogin(_ on: Bool) async {
        do {
            let reply = try await CommandSocketClient.send(
                .loginItemSet, arguments: [on ? "on" : "off"], to: AppIdentity.appSocketPath)
            login = Self.loginState(for: reply)
        } catch {
            login = .failed("snapit did not answer. Quit snapit and open it again.")
        }
    }

    private static func loginState(for reply: String) -> LoginState {
        if reply.hasPrefix("error ") { return .failed(String(reply.dropFirst(6))) }
        switch LoginItemStatus(rawValue: reply) {
        case .enabled: return .on
        case .requiresApproval: return .needsApproval
        case .notRegistered, .notFound: return .off
        case nil: return .failed("snapit answered \(reply)")
        }
    }

    /// Asks the menu bar app which combination each Shortcut has now: its registrar is the one
    /// truth, and what Settings stored may be older (another install, a failed apply).
    func refreshShortcuts() async {
        guard let reply = try? await CommandSocketClient.send(.shortcutCombos, to: AppIdentity.appSocketPath) else {
            return
        }
        for line in reply.split(separator: "\n") {
            let words = line.split(separator: " ").map(String.init)
            guard let id = words.first, let entry = ShortcutCatalog.entry(id: id),
                let combo = ShortcutCombo.parse(wire: Array(words.dropFirst()))
            else { continue }
            combos[id] = .some(combo)
            ShortcutSettings.store(combo, for: entry.shortcut)
        }
    }

    // MARK: Save location

    /// Shows the folder chooser. A scripted run never shows it: it sets the folder directly.
    func chooseSaveLocation(from window: NSWindow?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = saveLocation
        panel.prompt = "Choose"
        panel.message = "Choose the folder Save writes into"
        let accept: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in self?.setSaveLocation(url) }
        }
        if let window { panel.beginSheetModal(for: window, completionHandler: accept) } else { panel.begin(completionHandler: accept) }
    }

    func setSaveLocation(_ url: URL) {
        AppDefaults.store.set(url.path, forKey: GeneralSettings.saveLocationKey)
        saveLocation = url
    }

    // MARK: Capturing, Editor, Export

    func setAfterSelectingArea(_ value: AfterSelectingArea) {
        AppDefaults.store.set(value.rawValue, forKey: CapturingSettings.afterSelectingAreaKey)
        afterSelectingArea = value
    }

    func setCloseAfterCopy(_ value: Bool) {
        AppDefaults.store.set(value, forKey: EditorSettings.closeAfterCopyKey)
        closeAfterCopy = value
    }

    func setCloseAfterSave(_ value: Bool) {
        AppDefaults.store.set(value, forKey: EditorSettings.closeAfterSaveKey)
        closeAfterSave = value
    }

    func setStandardResolution(_ value: Bool) {
        AppDefaults.store.set(value, forKey: ExportSettings.standardResolutionKey)
        standardResolution = value
    }

    // MARK: Shortcuts

    func combo(for entry: ShortcutCatalog.Entry) -> ShortcutCombo? {
        combos[entry.shortcut.id] ?? nil
    }

    private func storedCombo(id: String) -> ShortcutCombo? { combos[id] ?? nil }

    /// Why a Shortcut deserves a second look: macOS uses the key combination, or another snapit
    /// Shortcut does. Nil when it is fine. The Shortcut still works; the note only flags it.
    func note(for entry: ShortcutCatalog.Entry) -> String? {
        guard let combo = combo(for: entry) else { return nil }
        if SystemShortcuts.current.isTaken(combo) { return "macOS also uses this key combination." }
        if let other = ShortcutCatalog.entries.first(where: {
            $0.shortcut.id != entry.shortcut.id && storedCombo(id: $0.shortcut.id) == combo
        }) {
            return "\(other.title) uses this key combination too."
        }
        return nil
    }

    /// Starts listening for the keys of the Shortcut `entry`. Esc cancels, Delete clears it, and a
    /// key with ⌘, ⌃ or ⌥ (or a function key) is the new combination.
    func beginRecording(_ entry: ShortcutCatalog.Entry) {
        cancelRecording()
        recordingID = entry.shortcut.id
        shortcutError = nil
        recorder.start { [weak self] result in
            switch result {
            case .cancel: self?.cancelRecording()
            case .clear: self?.record(nil, for: entry)
            case .accept(let combo): self?.record(combo, for: entry)
            case .needsModifier: break
            }
        }
    }

    func cancelRecording() {
        recorder.stop()
        recordingID = nil
    }

    /// Gives a Shortcut its new combination: kept in the defaults, then applied by the menu bar
    /// app, whose menu shows it from then on.
    func record(_ combo: ShortcutCombo?, for entry: ShortcutCatalog.Entry) {
        cancelRecording()
        ShortcutSettings.store(combo, for: entry.shortcut)
        combos[entry.shortcut.id] = .some(combo)
        applying = Task {
            do {
                let reply = try await CommandSocketClient.send(
                    .applyShortcut, arguments: [entry.shortcut.id] + ShortcutCombo.wire(combo).split(separator: " ").map(String.init),
                    to: AppIdentity.appSocketPath)
                shortcutError = reply == "ok" ? nil : "snapit could not use this Shortcut: \(reply)"
            } catch {
                shortcutError = "snapit did not answer. Quit snapit and open it again."
            }
        }
    }

    func openScreenshotShortcuts() {
        SystemSettingsLinks.open(.screenshotShortcuts)
    }

    func openLoginItems() {
        SystemSettingsLinks.open(.loginItems)
    }
}
