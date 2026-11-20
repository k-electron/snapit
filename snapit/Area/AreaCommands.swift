import AppKit
import Foundation

nonisolated extension SocketCommand {
    /// `fixture-extra-display <scale> <point width> <point height>` adds a second fake display to
    /// the right of the first; `fixture-extra-display none` takes it away. Replies `ok`.
    static let fixtureExtraDisplay = SocketCommand("fixture-extra-display")
    /// Waits until the overlay that is showing has finished, then replies `opened <N>` (Capture N
    /// is in the Editor), `cancelled` or `failed <why>`.
    static let overlayWait = SocketCommand("overlay-wait")
    /// `overlay-mouse move|down|drag|up <display> <x> <y>`: sends the overlay a mouse event at a
    /// point of display `<display>` (0 is the first), in points from that display's top-left
    /// corner. A real `NSEvent`, delivered to the display's panel. Replies `ok`.
    static let overlayMouse = SocketCommand("overlay-mouse")
    /// `overlay-key escape|enter|<key code>`: sends the overlay a key event through the
    /// application's event dispatch. Replies `ok`.
    static let overlayKey = SocketCommand("overlay-key")
    /// What the overlay shows now, as `key=value` lines. Replies `none` when no overlay is up.
    static let overlayFacts = SocketCommand("overlay-facts")
    /// `overlay-snapshot <display> <path>`: renders that display's layers to a PNG inside the
    /// run's root, as the panel would show them. Replies `ok`.
    static let overlaySnapshot = SocketCommand("overlay-snapshot")
}

extension SocketCommandRegistry {
    /// The Area overlay's test-mode commands. They exist only while test mode is on.
    func registerAreaTestCommands() {
        guard TestMode.isActive else { return }

        register(.fixtureExtraDisplay) { request in
            let arguments = request.arguments
            if arguments.first == "none" {
                FixtureAreaCaptureSource.shared.extraDisplay = nil
                return "ok"
            }
            let numbers = arguments.compactMap(Int.init)
            guard numbers.count == 3, (1...3).contains(numbers[0]), numbers[1] > 0, numbers[2] > 0 else {
                return "error fixture-extra-display <scale 1-3> <points w> <points h> | none"
            }
            FixtureAreaCaptureSource.shared.extraDisplay = FixtureCaptureSource.Display(
                scale: numbers[0], pointWidth: numbers[1], pointHeight: numbers[2])
            return "ok"
        }
        register(.overlayWait) { _ in
            switch await AreaCaptureFlow.waitForResult() {
            case .opened(let number): "opened \(number)"
            case .cancelled: "cancelled"
            case .failed(let why): "failed \(why)"
            }
        }
        register(.overlayMouse) { request in
            guard let controller = AreaCaptureFlow.activeOverlay else { return "error no overlay" }
            let arguments = request.arguments
            guard arguments.count == 4, let display = Int(arguments[1]), let x = Double(arguments[2]),
                let y = Double(arguments[3]), controller.views.indices.contains(display)
            else { return "error overlay-mouse move|down|drag|up <display> <x> <y>" }
            guard controller.send(arguments[0], display: display, point: CGPoint(x: x, y: y)) else {
                return "error unknown mouse event \(arguments[0])"
            }
            return "ok"
        }
        register(.overlayKey) { request in
            guard let controller = AreaCaptureFlow.activeOverlay, let panel = controller.panels.first else {
                return "error no overlay"
            }
            let keyCodes = ["escape": 53, "enter": 36]
            guard let name = request.arguments.first, let keyCode = keyCodes[name] ?? Int(name) else {
                return "error overlay-key escape|enter|<key code>"
            }
            let event = NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: panel.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "",
                isARepeat: false, keyCode: UInt16(keyCode))
            guard let event else { return "error no key event" }
            NSApp.sendEvent(event)
            return "ok"
        }
        register(.overlayFacts) { _ in
            guard let controller = AreaCaptureFlow.activeOverlay else { return "none" }
            return controller.facts().joined(separator: "\n")
        }
        register(.overlaySnapshot) { request in
            guard let controller = AreaCaptureFlow.activeOverlay else { return "error no overlay" }
            let arguments = request.arguments
            guard arguments.count == 2, let display = Int(arguments[0]), controller.views.indices.contains(display),
                TestMode.root.map({ arguments[1].hasPrefix($0.path + "/") && !arguments[1].contains("..") }) ?? false
            else { return "error overlay-snapshot <display> <path inside the root>" }
            guard let png = controller.snapshotPNG(display: display) else { return "error could not render" }
            do {
                try png.write(to: URL(fileURLWithPath: arguments[1]))
                return "ok"
            } catch {
                return "error \(error)"
            }
        }
    }
}

/// Test mode's way into the overlay: real events through the real dispatch, and a report of what
/// it shows.
extension AreaOverlayController {
    private static var eventNumber = 0

    /// Sends a mouse event of `kind` to the panel of `display`. `move` goes to the view the way a
    /// tracking area delivers it; the others go through the panel's own event dispatch.
    func send(_ kind: String, display: Int, point: CGPoint) -> Bool {
        let types: [String: NSEvent.EventType] = [
            "move": .mouseMoved, "down": .leftMouseDown, "drag": .leftMouseDragged, "up": .leftMouseUp,
        ]
        guard let type = types[kind] else { return false }
        let panel = panels[display], view = views[display]
        Self.eventNumber += 1
        guard
            let event = NSEvent.mouseEvent(
                with: type, location: CGPoint(x: point.x, y: view.bounds.height - point.y), modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber, context: nil,
                eventNumber: Self.eventNumber, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1)
        else { return false }
        if type == .mouseMoved { view.mouseMoved(with: event) } else { panel.sendEvent(event) }
        return true
    }

    func facts() -> [String] {
        func describe(_ rect: CGRect?) -> String {
            guard let rect else { return "none" }
            return "\(format(rect.minX)),\(format(rect.minY)) \(format(rect.width))x\(format(rect.height))"
        }
        let layerHosted = views.allSatisfy { $0.layer === $0.scene.root && $0.layer?.delegate !== $0 }
        return [
            "displays=\(displays.count)",
            "state=\(state.rawValue)",
            "display=\(activeIndex)",
            "cursor=\(format(cursor.x)),\(format(cursor.y))",
            "hover=\(describe(hoveredWindow))",
            "selection=\(selectionIndex.map(String.init) ?? "none") \(describe(selection))",
            "view=\(layerHosted ? "layer-hosted" : "drawn")",
            "scene-updates=\(views.reduce(0) { $0 + $1.scene.updateCount })",
            "shown-ms=\(AreaCaptureFlow.lastShownMilliseconds.map { String(format: "%.1f", $0) } ?? "none")",
        ]
    }

    private func format(_ value: Double) -> String {
        var text = String(format: "%.2f", value)
        while text.contains("."), text.hasSuffix("0") || text.hasSuffix(".") { text.removeLast() }
        return text
    }

    /// The display's layers rendered into a PNG, as pixels of the display's scale.
    func snapshotPNG(display index: Int) -> Data? {
        let display = displays[index]
        let scale = display.scale
        let width = Int(display.frame.width * scale), height = Int(display.frame.height * scale)
        guard
            let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.scaleBy(x: scale, y: scale)
        views[index].scene.root.render(in: context)
        guard let image = context.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }
}
