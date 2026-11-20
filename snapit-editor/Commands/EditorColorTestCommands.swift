import AppKit

nonisolated extension SocketCommand {
    /// `editor-color-panel <N> state | choose <RRGGBB> | drag <RRGGBB>...`: the color panel's fixture
    /// (test mode has no real panel). `state` replies `shown=yes|no color=RRGGBB`; `choose` is a
    /// value typed into the panel (the mouse button up); `drag` is a drag across the colors with the
    /// button down, then released by a real mouse-up event. Test mode only.
    static let editorColorPanel = SocketCommand("editor-color-panel")
}

extension SocketCommandRegistry {
    func registerEditorColorTestCommands() {
        guard TestMode.isActive else { return }

        register(.editorColorPanel) { request in
            let arguments = request.arguments
            let panel = FixtureColorPanel.shared
            // The panel's state does not need an Editor: it is what is left after the last one closes.
            if arguments.count >= 2, arguments[1] == "state" {
                let color = panel.color.usingColorSpace(.sRGB) ?? panel.color
                let hex = AnnotationColor(
                    red: Double(color.redComponent), green: Double(color.greenComponent), blue: Double(color.blueComponent)).hex
                return "shown=\(panel.isShown ? "yes" : "no") color=\(hex)"
            }
            guard let session = Self.session(arguments), arguments.count >= 2, let window = session.window
            else { return "error editor-color-panel <N> state | choose <RRGGBB> | drag <RRGGBB>..." }
            switch arguments[1] {
            case "choose":
                guard arguments.count == 3, let color = AnnotationColor(hex: arguments[2]) else { return "error choose <RRGGBB>" }
                panel.isDragging = false
                panel.choose(NSColor(cgColor: color.cgColor) ?? .red)
                return "ok"
            case "drag":
                let colors = arguments.dropFirst(2).compactMap(AnnotationColor.init(hex:))
                guard !colors.isEmpty else { return "error drag <RRGGBB>..." }
                panel.isDragging = true
                for color in colors { panel.choose(NSColor(cgColor: color.cgColor) ?? .red) }
                panel.isDragging = false
                guard
                    let up = NSEvent.mouseEvent(
                        with: .leftMouseUp, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                        windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 0)
                else { return "error no mouse event" }
                NSApp.sendEvent(up)
                return "ok"
            default:
                return "error unknown subcommand \(arguments[1])"
            }
        }
    }
}
