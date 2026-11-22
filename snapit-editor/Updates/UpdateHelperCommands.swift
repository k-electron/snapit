import AppKit

nonisolated extension SocketCommand {
    /// Facts about the update window, one `key=value` line each: `window`, `title`, `activation`,
    /// `state` (`checking`, `newer`, `downloading`, `installing`, `up-to-date`, `unreachable`),
    /// `headline`, `detail`, `reminder`, `url`, `notes` (percent-encoded), `notes-bytes`,
    /// `notes-blocks`, `progress` (`<bytes received>/<bytes in all>` while it downloads, `?` for a
    /// size not known; empty otherwise), `progress-percent` (empty when not known), `cancel`
    /// (`enabled`, `disabled` from the swap on, `none` without a Cancel button) and `close-button`
    /// (the title bar's, `enabled` or `disabled`); then one `notes-block <kind>|<text>` line per
    /// block of the rendered notes and one `button <id>|<title>|<tooltip>` line per button. Test
    /// mode only.
    static let updateFacts = SocketCommand("update-facts")
    /// `update-press update|cancel|release-page|close`: presses a button of the update window
    /// (`close` is the title bar's close button). `update` replies at once, while the Update goes
    /// on; `cancel` and `close` reply `error ...` when the swap has begun and they are disabled.
    /// Test mode only.
    static let updatePress = SocketCommand("update-press")
    /// `update-snapshot <png path>`: renders the window's view to a PNG inside the run's root. Test
    /// mode only.
    static let updateSnapshot = SocketCommand("update-snapshot")
}

extension SocketCommandRegistry {
    func registerUpdateHelperCommands() {
        register(.showUpdateCheck) { _ in
            UpdateWindow.showAndCheck()
            // The window is on screen when the reply goes out, not just ordered front.
            CATransaction.flush()
            return "ok"
        }
        guard TestMode.isActive else { return }
        register(.updateFacts) { _ in UpdateFacts.describe() }
        register(.updatePress) { request in
            guard let model = UpdateWindow.shared?.model else { return "error no update window" }
            switch request.arguments.first {
            case "update":
                guard model.buttons.contains(where: { $0.id == model.updateButton.id }) else { return "error nothing to update" }
                model.update()
            case "cancel":
                guard model.canCancel else { return "error nothing to cancel" }
                model.cancel()
            case "release-page":
                guard model.releasePageURL != nil else { return "error no release page" }
                model.openReleasePage()
            case "close":
                guard model.canClose else { return "error the window cannot close while the Update swaps in the new copy" }
                // The title bar's own close button: it asks the window's delegate, as a click does.
                UpdateWindow.shared?.window?.performClose(nil)
            default: return "error update-press update|cancel|release-page|close"
            }
            return "ok"
        }
        register(.updateSnapshot) { request in
            guard let window = UpdateWindow.shared?.window, let view = window.contentView, let path = request.arguments.first,
                let root = TestMode.root?.standardizedFileURL.path,
                URL(fileURLWithPath: path).standardizedFileURL.path.hasPrefix(root + "/"),
                let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)
            else { return "error update-snapshot <png path inside the test root>" }
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
}

/// What the scripted run reads of the update window.
@MainActor
enum UpdateFacts {
    static func describe() -> String {
        guard let update = UpdateWindow.shared, let window = update.window else { return "window=none" }
        let model = update.model
        var lines = [
            "window=\(window.isVisible ? "visible" : "hidden")",
            "title=\(window.title)",
            "activation=\(NSApp.activationPolicy() == .regular ? "regular" : "accessory")",
            "state=\(model.stateName)",
            "headline=\(model.headline)",
            "detail=\(model.detail ?? "")",
            "reminder=\(model.reminder ?? "")",
            "url=\(model.releasePageURL?.absoluteString ?? "")",
            "notes=\(encoded(model.notes ?? ""))",
        ]
        lines.append("progress=\(progressText(model))")
        lines.append("progress-percent=\(model.isInstalling ? model.progress.percent.map(String.init) ?? "" : "")")
        lines.append("cancel=\(model.buttons.contains { $0.id == model.cancelButton.id } ? (model.canCancel ? "enabled" : "disabled") : "none")")
        lines.append("close-button=\(update.closeButtonEnabled.map { $0 ? "enabled" : "disabled" } ?? "none")")
        lines.append("notes-bytes=\((model.notes ?? "").utf8.count)")
        lines.append("notes-blocks=\(model.blocks.count)")
        for block in model.blocks {
            lines.append("notes-block \(block.kind.rawValue)|\(block.plainText)")
        }
        lines += model.buttons.map(\.factsLine)
        return lines.joined(separator: "\n")
    }

    private static func progressText(_ model: UpdateModel) -> String {
        guard model.isInstalling, case .downloading(let received, let total) = model.progress else { return "" }
        return "\(received)/\(total.map(String.init) ?? "?")"
    }

    /// Percent-encoded as `SocketRequest` encodes an argument, so a run can compare it with text it
    /// sent without handling lines.
    private static func encoded(_ text: String) -> String {
        SocketRequest(command: .echo, arguments: [text]).line.dropFirst(5).description
    }
}
