import AppKit

nonisolated extension SocketCommand {
    /// Facts about the update window, one `key=value` line each: `window`, `title`, `activation`,
    /// `state` (`checking`, `newer`, `up-to-date`, `unreachable`), `headline`, `detail`, `reminder`,
    /// `url`, `notes` (percent-encoded), `notes-bytes`, `notes-blocks`; then one `notes-block <kind>|<text>` line per block of the
    /// rendered notes and one `button <id>|<title>|<tooltip>` line per button. Test mode only.
    static let updateFacts = SocketCommand("update-facts")
    /// `update-press download|close`: presses a button of the update window. Test mode only.
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
            case "download":
                guard model.downloadURL != nil else { return "error nothing to download" }
                model.download()
            case "close": model.close()
            default: return "error update-press download|close"
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
            "state=\(model.state.name)",
            "headline=\(model.headline)",
            "detail=\(model.detail ?? "")",
            "reminder=\(model.reminder ?? "")",
            "url=\(model.downloadURL?.absoluteString ?? "")",
            "notes=\(encoded(model.notes ?? ""))",
        ]
        lines.append("notes-bytes=\((model.notes ?? "").utf8.count)")
        lines.append("notes-blocks=\(model.blocks.count)")
        for block in model.blocks {
            lines.append("notes-block \(block.kind.rawValue)|\(block.plainText)")
        }
        lines += model.buttons.map(\.factsLine)
        return lines.joined(separator: "\n")
    }

    /// Percent-encoded as `SocketRequest` encodes an argument, so a run can compare it with text it
    /// sent without handling lines.
    private static func encoded(_ text: String) -> String {
        SocketRequest(command: .echo, arguments: [text]).line.dropFirst(5).description
    }
}
