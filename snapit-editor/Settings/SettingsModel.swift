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
    /// The key combination of each Shortcut, as the menu bar app's registrar has it. Empty until
    /// the menu bar app has answered (`refreshShortcuts`), which the recorders wait for.
    private(set) var combos: [String: ShortcutCombo?] = [:]
    /// The Shortcut being recorded (its id), if any.
    private(set) var recordingID: String?
    /// Why the key just pressed was not taken as a Shortcut, while one is recording.
    private(set) var recordingHint: String?
    private(set) var shortcutError: String?
    /// A flag under each Shortcut's recorder: macOS also uses its keys, or it took them over.
    private(set) var notes: [String: String] = [:]
    /// The menu bar app being told about the latest recorded Shortcut.
    @ObservationIgnored private(set) var applying: Task<Void, Never>?

    @ObservationIgnored private let recorder = ShortcutRecorder()

    var shortcutsLoaded: Bool { !combos.isEmpty }

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

    /// Asks the menu bar app which combination each Shortcut has now. Its registrar is the one
    /// truth: Settings keeps no copy of its own.
    func refreshShortcuts() async {
        guard let reply = try? await CommandSocketClient.send(.shortcutCombos, to: AppIdentity.appSocketPath) else {
            return
        }
        for line in reply.split(separator: "\n") {
            let words = line.split(separator: " ").map(String.init)
            guard let id = words.first, ShortcutCatalog.entry(id: id) != nil,
                let combo = ShortcutCombo.parse(wire: Array(words.dropFirst()))
            else { continue }
            combos[id] = .some(combo)
        }
        recomputeNotes(keeping: [:])
    }

    // MARK: Save location

    /// Shows the folder chooser. A scripted run never shows it: it sets the folder directly.
    func chooseSaveLocation(from window: NSWindow?) {
        SaveLocationChooser.choose(startingAt: saveLocation, from: window) { [weak self] url in self?.setSaveLocation(url) }
    }

    func setSaveLocation(_ url: URL) {
        SaveLocationChooser.set(url)
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

    func note(for entry: ShortcutCatalog.Entry) -> String? { notes[entry.shortcut.id] }

    /// Flags the Shortcuts macOS also uses (the system's table is read once per change, not per
    /// draw). `kept` are the notes that stay (a take-over's).
    private func recomputeNotes(keeping kept: [String: String]) {
        var result = kept
        for entry in ShortcutCatalog.entries where result[entry.shortcut.id] == nil {
            if let combo = combo(for: entry), SystemShortcuts.current.isTaken(combo) {
                result[entry.shortcut.id] = "macOS also uses this key combination."
            }
        }
        notes = result
    }

    /// Starts listening for the keys of the Shortcut `entry`. Esc cancels, Delete clears it, and a
    /// key that is safe as a global Shortcut is the new combination (see `ShortcutRecorder`).
    func beginRecording(_ entry: ShortcutCatalog.Entry) {
        guard shortcutsLoaded else { return }
        cancelRecording()
        recordingID = entry.shortcut.id
        recordingHint = nil
        shortcutError = nil
        recorder.start { [weak self] result in
            switch result {
            case .cancel: self?.cancelRecording()
            case .clear: self?.record(nil, for: entry)
            case .accept(let combo): self?.record(combo, for: entry)
            case .rejected(let hint):
                self?.recordingHint = hint
                if !TestMode.isActive { NSSound.beep() }
            }
        }
    }

    func cancelRecording() {
        recorder.stop()
        recordingID = nil
        recordingHint = nil
    }

    /// Gives a Shortcut its new combination and has the menu bar app apply it, so the menu shows
    /// it from then on. Two Shortcuts never share keys (both actions would run on one press): a
    /// Shortcut that had the combination loses it, and the recorder says so.
    func record(_ combo: ShortcutCombo?, for entry: ShortcutCatalog.Entry) {
        cancelRecording()
        var kept: [String: String] = [:]
        var applies: [(id: String, combo: ShortcutCombo?)] = []
        if let combo {
            for other in ShortcutCatalog.entries where other.shortcut.id != entry.shortcut.id {
                if self.combo(for: other) == combo {
                    combos[other.shortcut.id] = .some(nil)
                    applies.append((other.shortcut.id, nil))
                    kept[entry.shortcut.id] = "Removed from \(other.title)."
                }
            }
        }
        combos[entry.shortcut.id] = .some(combo)
        applies.append((entry.shortcut.id, combo))
        recomputeNotes(keeping: kept)
        applying = Task {
            do {
                for apply in applies {
                    let reply = try await CommandSocketClient.send(
                        .applyShortcut, arguments: [apply.id] + ShortcutCombo.wire(apply.combo).split(separator: " ").map(String.init),
                        to: AppIdentity.appSocketPath)
                    if reply != "ok" {
                        shortcutError = "snapit could not use this Shortcut: \(reply)"
                        await refreshShortcuts()
                        return
                    }
                }
                shortcutError = nil
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
