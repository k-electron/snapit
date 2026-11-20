import AppKit

nonisolated extension SocketCommand {
    /// Facts about the Settings window: `window`, `title`, `activation`, then per section a
    /// `section <title>` line and one `control <id>|<kind>|<title>|<value>|<tooltip>` line per
    /// control (a Shortcut's value is `none` or `<key code> <modifiers>`, followed by
    /// `note <id>|<text>` when it is flagged). Test mode only.
    static let settingsFacts = SocketCommand("settings-facts")
    /// `settings-press <control id> [<value>]`: does what clicking the control does: flips a
    /// switch, picks an option, starts a recorder (`shortcut.<id>`), clears one
    /// (`shortcut-clear.<id>`), presses a button. Test mode only.
    static let settingsPress = SocketCommand("settings-press")
    /// `settings-key <key code> [<modifier>,...]`: a key press as the window receives it (the
    /// recorder's). Replies `ok` once the menu bar app has been told. Test mode only.
    static let settingsKey = SocketCommand("settings-key")
    /// `settings-choose-save-location <folder>`: what choosing a folder in the chooser does. The
    /// folder must be inside the run's root. Test mode only.
    static let settingsChooseSaveLocation = SocketCommand("settings-choose-save-location")
    /// `settings-snapshot <png path>`: renders the page's view to a PNG inside the run's root, so a
    /// look at the page needs no screen. Test mode only.
    static let settingsSnapshot = SocketCommand("settings-snapshot")
    /// Presses the window's close button. The helper quits when no other window is open, so a
    /// reply may never come: wait for the process to go. Test mode only.
    static let settingsClose = SocketCommand("settings-close")
}

extension SocketCommandRegistry {
    func registerSettingsHelperCommands() {
        register(.showSettings) { _ in
            SettingsWindow.show()
            // The window is on screen when the reply goes out, not just ordered front.
            CATransaction.flush()
            return "ok"
        }
        guard TestMode.isActive else { return }
        register(.settingsFacts) { _ in SettingsFacts.describe() }
        register(.settingsPress) { request in await SettingsFacts.press(request.arguments) }
        register(.settingsKey) { request in await SettingsFacts.key(request.arguments) }
        register(.settingsSnapshot) { request in
            guard let window = SettingsWindow.shared?.window, let view = window.contentView, let path = request.arguments.first,
                let root = TestMode.root?.standardizedFileURL.path,
                URL(fileURLWithPath: path).standardizedFileURL.path.hasPrefix(root + "/"),
                let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)
            else { return "error settings-snapshot <png path inside the test root>" }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            guard let png = bitmap.representation(using: .png, properties: [:]) else { return "error no png" }
            do {
                try png.write(to: URL(fileURLWithPath: path))
                return "ok"
            } catch {
                return "error \(error)"
            }
        }
        register(.settingsClose) { _ in
            guard let window = SettingsWindow.shared?.window else { return "error no Settings window" }
            window.performClose(nil)
            return "ok"
        }
        register(.settingsChooseSaveLocation) { request in
            guard let settings = SettingsWindow.shared, let path = request.arguments.first else {
                return "error no Settings window"
            }
            guard let root = TestMode.root?.standardizedFileURL.path,
                URL(fileURLWithPath: path).standardizedFileURL.path.hasPrefix(root + "/")
            else { return "error folder must be inside the test root" }
            settings.model.setSaveLocation(URL(fileURLWithPath: path, isDirectory: true))
            return "ok"
        }
    }
}

/// What the scripted run reads of the Settings window, and the ways it clicks it.
@MainActor
enum SettingsFacts {
    static func describe() -> String {
        guard let settings = SettingsWindow.shared, let window = settings.window else { return "window=none" }
        let model = settings.model
        var lines = [
            "window=\(window.isVisible ? "visible" : "hidden")",
            "title=\(window.title)",
            "activation=\(NSApp.activationPolicy() == .regular ? "regular" : "accessory")",
        ]
        func control(_ control: SettingsControl, _ kind: String, _ value: String) {
            lines.append("control \(control.id)|\(kind)|\(control.title)|\(value)|\(control.tooltip)")
        }
        func onOff(_ value: Bool) -> String { value ? "on" : "off" }
        for section in SettingsSection.allCases {
            lines.append("section \(section.rawValue)")
            switch section {
            case .general:
                control(.openAtLogin, "switch", loginValue(model.login))
                control(.saveLocation, "path", model.saveLocation.path)
                control(.chooseSaveLocation, "button", "")
            case .capturing:
                for choice in AfterSelectingArea.allCases {
                    lines.append(
                        "control \(SettingsControl.afterSelectingArea.id)|option|\(choice.settingsTitle)|"
                            + "\(choice == model.afterSelectingArea ? "selected" : "unselected")|\(choice.settingsTooltip)")
                }
            case .editor:
                control(.closeAfterCopy, "switch", onOff(model.closeAfterCopy))
                control(.closeAfterSave, "switch", onOff(model.closeAfterSave))
            case .shortcuts:
                for entry in ShortcutCatalog.entries {
                    let combo = model.combo(for: entry)
                    let recording = model.recordingID == entry.shortcut.id
                    control(
                        .shortcut(entry), "recorder",
                        !model.shortcutsLoaded ? "unknown" : recording ? "recording" : ShortcutCombo.wire(combo))
                    if recording, let hint = model.recordingHint { lines.append("hint \(entry.shortcut.id)|\(hint)") }
                    if let combo { lines.append("display \(entry.shortcut.id)|\(combo.displayString)") }
                    if let note = model.note(for: entry) { lines.append("note \(entry.shortcut.id)|\(note)") }
                }
                control(.openScreenshotShortcuts, "button", "")
            case .export:
                control(.standardResolution, "switch", onOff(model.standardResolution))
            case .about:
                for row in AboutRows.all {
                    switch row.content {
                    case .text(let text): control(row.control, "text", text())
                    case .button: control(row.control, "button", "")
                    }
                }
            }
        }
        return lines.joined(separator: "\n")
    }

    static func loginValue(_ state: SettingsModel.LoginState) -> String {
        switch state {
        case .unknown: "unknown"
        case .on: "on"
        case .off: "off"
        case .needsApproval: "needs-approval"
        case .failed(let message): "failed \(message)"
        }
    }

    static func press(_ arguments: [String]) async -> String {
        guard let settings = SettingsWindow.shared, let id = arguments.first else { return "error settings-press <control id> [<value>]" }
        let model = settings.model
        let value = arguments.dropFirst().first
        switch id {
        case SettingsControl.openAtLogin.id:
            await model.setOpenAtLogin(model.login != .on)
        case SettingsControl.afterSelectingArea.id:
            guard let choice = value.flatMap(AfterSelectingArea.init(rawValue:)) else {
                return "error settings-press after-selecting-area showActionBar|captureOnRelease"
            }
            model.setAfterSelectingArea(choice)
        case SettingsControl.closeAfterCopy.id: model.setCloseAfterCopy(!model.closeAfterCopy)
        case SettingsControl.closeAfterSave.id: model.setCloseAfterSave(!model.closeAfterSave)
        case SettingsControl.standardResolution.id: model.setStandardResolution(!model.standardResolution)
        case SettingsControl.openScreenshotShortcuts.id: model.openScreenshotShortcuts()
        default:
            if id.hasPrefix("shortcut."), let entry = ShortcutCatalog.entry(id: String(id.dropFirst("shortcut.".count))) {
                if model.recordingID == entry.shortcut.id { model.cancelRecording() } else { model.beginRecording(entry) }
            } else if id.hasPrefix("shortcut-clear."),
                let entry = ShortcutCatalog.entry(id: String(id.dropFirst("shortcut-clear.".count)))
            {
                model.record(nil, for: entry)
                await model.applying?.value
            } else {
                return "error no control \(id)"
            }
        }
        return "ok"
    }

    static func key(_ arguments: [String]) async -> String {
        guard let settings = SettingsWindow.shared, let window = settings.window else { return "error no Settings window" }
        return await RecorderKeyEvent.send(arguments, to: window, model: settings.model)
    }
}
