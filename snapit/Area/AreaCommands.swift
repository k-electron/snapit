import AppKit
import Foundation

nonisolated extension SocketCommand {
    /// `fixture-extra-display <scale> <point width> <point height> [right|left|above]` adds a
    /// second fake display next to the first (to its right unless told otherwise; left and above
    /// put it at negative coordinates); `fixture-extra-display none` takes it away. Replies `ok`.
    static let fixtureExtraDisplay = SocketCommand("fixture-extra-display")
    /// `fixture-pixel-layout alpha-first|skip-first`: the layout of the first fake display's frozen
    /// image. `skip-first` is BGRX from a plain bitmap context, which the engine's in-place crop
    /// does not take, so the Capture is cropped through its fallback. Replies `ok`.
    static let fixturePixelLayout = SocketCommand("fixture-pixel-layout")
    /// Tells the overlay the displays changed, as macOS does when one is plugged in, unplugged or
    /// rearranged: the overlay ends. Replies `ok`.
    static let overlayScreensChanged = SocketCommand("overlay-screens-changed")
    /// The notification macOS posts for a Dock that moved or a display that changed nothing: the displays
    /// are what they were, so an overlay or a countdown carries on. Replies `ok`.
    static let overlayScreensNoise = SocketCommand("overlay-screens-noise")
    /// Waits until the overlay that is showing has finished, then replies `opened <N>` (Capture N
    /// is in the Editor), `cancelled` or `failed <why>`.
    static let overlayWait = SocketCommand("overlay-wait")
    /// `overlay-frames-freed`: `yes` when the frozen frames of the latest overlay are all gone (its
    /// panels, scenes and controller have let go and the flow kept none), `no` while one is still held,
    /// `none` before any overlay, `unknown` when a frame carried no lifetime probe. Test mode only.
    static let overlayFramesFreed = SocketCommand("overlay-frames-freed")
    /// `overlay-panels-freed`: `yes` when the latest overlay's controller, panels and scene views are all
    /// deallocated; `no <names>` lists those still alive; `none` before any overlay. Test mode only.
    static let overlayPanelsFreed = SocketCommand("overlay-panels-freed")
    /// What the app's windows are now: `windows total=<n> visible=<v>`, one `window <class> total=<n>
    /// visible=<v>` line per class, `overlay <overlay-panels-freed's answer>` and `toast-panel
    /// alive|gone`. For a failed memory check's log. Test mode only.
    static let liveWindows = SocketCommand("live-windows")
    /// Shows a one point panel and closes it, with a Core Animation commit before and after: a round trip to
    /// the window server, to see whether memory is waiting for one. Replies `ok`. Test mode only.
    static let caNudge = SocketCommand("ca-nudge")
    /// `overlay-mouse move|down|drag|up <display> <x> <y> [<click count>]`: sends the overlay a
    /// mouse event at a point of display `<display>` (0 is the first), in points from that
    /// display's top-left corner. A real `NSEvent`, delivered to the display's panel, with that
    /// click count (1 when omitted; a double-click is a `down` with 2). Replies `ok`.
    static let overlayMouse = SocketCommand("overlay-mouse")
    /// `overlay-key escape|enter|left|right|up|down|<letter>|<key code> [shift]`: sends the overlay a
    /// key event through the application's event dispatch. Replies `ok`.
    static let overlayKey = SocketCommand("overlay-key")
    /// What the overlay shows now, as `key=value` lines. Replies `none` when no overlay is up.
    static let overlayFacts = SocketCommand("overlay-facts")
    /// How many windows the app has ordered in at the overlay's level (the overlay's panels, the
    /// Color picker's toast, a Timed Capture's border and badge): what the window server's list
    /// (`png-inspect overlay-windows`) shows once it has caught up. The scripted run waits for the
    /// two to agree, because the list lags AppKit's `orderFront` and `orderOut` when the machine is busy.
    static let overlayWindowCount = SocketCommand("overlay-window-count")
    /// `overlay-snapshot <display> <path>`: renders that display's layers to a PNG inside the
    /// run's root, as the panel would show them. Replies `ok`.
    static let overlaySnapshot = SocketCommand("overlay-snapshot")
}

extension SocketCommandRegistry {
    /// The Area overlay's test-mode commands. They exist only while test mode is on.
    func registerAreaTestCommands() {
        guard TestMode.isActive else { return }
        registerActionBarTestCommands()
        registerPickColorTestCommands()
        registerTimedCaptureTestCommands()

        register(.fixtureExtraDisplay) { request in
            let arguments = request.arguments
            if arguments.first == "none" {
                FixtureAreaCaptureSource.shared.extraDisplay = nil
                return "ok"
            }
            let numbers = arguments.compactMap(Int.init)
            let placement = arguments.count > 3 ? FixtureAreaCaptureSource.Placement(rawValue: arguments[3]) : .right
            guard numbers.count == 3, (1...3).contains(numbers[0]), numbers[1] > 0, numbers[2] > 0, let placement else {
                return "error fixture-extra-display <scale 1-3> <points w> <points h> [right|left|above] | none"
            }
            FixtureAreaCaptureSource.shared.extraPlacement = placement
            FixtureAreaCaptureSource.shared.extraDisplay = FixtureCaptureSource.Display(
                scale: numbers[0], pointWidth: numbers[1], pointHeight: numbers[2])
            return "ok"
        }
        register(.overlayFramesFreed) { _ in AreaCaptureFlow.overlayFramesFreed }
        register(.overlayPanelsFreed) { _ in AreaCaptureFlow.overlayObjectsAlive }
        register(.liveWindows) { _ in
            var classes: [String: (total: Int, visible: Int)] = [:]
            for window in NSApp.windows {
                let name = String(describing: type(of: window))
                var entry = classes[name] ?? (0, 0)
                entry.total += 1
                if window.isVisible { entry.visible += 1 }
                classes[name] = entry
            }
            var lines = ["windows total=\(NSApp.windows.count) visible=\(NSApp.windows.filter(\.isVisible).count)"]
            for (name, entry) in classes.sorted(by: { $0.key < $1.key }) {
                lines.append("window \(name) total=\(entry.total) visible=\(entry.visible)")
            }
            lines.append("overlay \(AreaCaptureFlow.overlayObjectsAlive)")
            lines.append("toast-panel \(ColorToast.panelForTest == nil ? "gone" : "alive")")
            return lines.joined(separator: "\n")
        }
        register(.caNudge) { _ in
            CATransaction.flush()
            let panel = NSPanel(
                contentRect: CGRect(x: 0, y: 0, width: 1, height: 1), styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false
            panel.ignoresMouseEvents = true
            panel.alphaValue = 0.01
            panel.level = .screenSaver
            panel.orderFrontRegardless()
            CATransaction.flush()
            panel.orderOut(nil)
            panel.close()
            CATransaction.flush()
            return "ok"
        }
        register(.fixturePixelLayout) { request in
            guard let layout = request.arguments.first, ["alpha-first", "skip-first"].contains(layout) else {
                return "error fixture-pixel-layout alpha-first|skip-first"
            }
            FixtureCaptureSource.shared.display.skipsAlpha = layout == "skip-first"
            return "ok"
        }
        register(.overlayScreensChanged) { _ in
            guard AreaCaptureFlow.activeOverlay != nil || AreaCaptureFlow.countdown != nil else {
                return "error no overlay"
            }
            DisplayConfiguration.simulateChange()
            NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: NSApp)
            return "ok"
        }
        register(.overlayScreensNoise) { _ in
            guard AreaCaptureFlow.activeOverlay != nil || AreaCaptureFlow.countdown != nil else {
                return "error no overlay"
            }
            NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: NSApp)
            return "ok"
        }
        register(.overlayWait) { _ in
            switch await AreaCaptureFlow.waitForResult() {
            case .opened(let number): "opened \(number)"
            case .pickedColor(let hex): "picked \(hex)"
            case .cancelled: "cancelled"
            case .permissionNeeded: "permission-needed"
            case .failed(let why): "failed \(why)"
            }
        }
        register(.overlayMouse) { request in
            guard let controller = AreaCaptureFlow.activeOverlay else { return "error no overlay" }
            let arguments = request.arguments
            guard (4...5).contains(arguments.count), let display = Int(arguments[1]), let x = Double(arguments[2]),
                let y = Double(arguments[3]), controller.views.indices.contains(display),
                let clicks = arguments.count == 5 ? Int(arguments[4]) : 1, clicks >= 1
            else { return "error overlay-mouse move|down|drag|up <display> <x> <y> [<click count>]" }
            guard controller.send(arguments[0], display: display, point: CGPoint(x: x, y: y), clickCount: clicks) else {
                return "error unknown mouse event \(arguments[0])"
            }
            return "ok"
        }
        register(.overlayKey) { request in
            guard let controller = AreaCaptureFlow.activeOverlay, let panel = controller.panels.first else {
                return "error no overlay"
            }
            // Letters are the ANSI keys' codes; the event carries the letter the way a keyboard's would.
            let letters = [
                "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12,
                "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38,
                "k": 40, "n": 45, "m": 46,
            ]
            let keyCodes = ["escape": 53, "enter": 36, "left": 123, "right": 124, "down": 125, "up": 126]
                .merging(letters) { $1 }
            guard let name = request.arguments.first, let keyCode = keyCodes[name] ?? Int(name),
                request.arguments.dropFirst().allSatisfy({ $0 == "shift" })
            else {
                return "error overlay-key escape|enter|left|right|up|down|<letter>|<key code> [shift]"
            }
            let characters = letters[name] == nil ? "" : name
            let event = NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: request.arguments.count > 1 ? [.shift] : [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: panel.windowNumber, context: nil, characters: characters,
                charactersIgnoringModifiers: characters, isARepeat: false, keyCode: UInt16(keyCode))
            guard let event else { return "error no key event" }
            NSApp.sendEvent(event)
            return "ok"
        }
        register(.overlayWindowCount) { _ in
            String(NSApp.windows.filter { $0.isVisible && $0.level == .screenSaver }.count)
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
    func send(_ kind: String, display: Int, point: CGPoint, clickCount: Int = 1) -> Bool {
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
                eventNumber: Self.eventNumber, clickCount: clickCount, pressure: type == .leftMouseUp ? 0 : 1)
        else { return false }
        if type == .mouseMoved { view.mouseMoved(with: event) } else { panel.sendEvent(event) }
        return true
    }

    func facts() -> [String] {
        func describe(_ rect: CGRect?) -> String {
            guard let rect else { return "none" }
            return "\(format(rect.minX)),\(format(rect.minY)) \(format(rect.width))x\(format(rect.height))"
        }
        // The scene view hosts the scene's layer and draws nothing; the container around it draws
        // nothing either (it updates its layer, which stays empty).
        let layerHosted = views.allSatisfy { $0.layer === $0.scene.root && $0.layer?.delegate !== $0 }
            && containers.allSatisfy { $0.wantsUpdateLayer && $0.subviews.first === $0.sceneView }
        return [
            "displays=\(displays.count)",
            "mode=\(mode)",
            "state=\(state.rawValue)",
            "display=\(activeIndex)",
            "display-ids=\(displays.map { String($0.displayID) }.joined(separator: ","))",
            "cursor=\(format(cursor.x)),\(format(cursor.y))",
            "hover=\(describe(hoveredWindow))",
            "hover-window=\(hoveredOnScreenWindow.map { String($0.id) } ?? "none")",
            "area=\(areaDisplayIndex.map(String.init) ?? "none") \(describe(area))",
            "view=\(layerHosted ? "layer-hosted-scene" : "drawn")",
            "after-selecting=\(CapturingSettings.afterSelectingArea.rawValue)",
            "handles=\(views.reduce(0) { $0 + $1.scene.visibleHandles })",
            "action-bar=\(describe(containers.lazy.compactMap(\.actionBarFrame).first))",
            "loupe=\(views.contains { $0.scene.isLoupeShown } ? "shown" : "hidden")",
            "hovered=\(hoveredTile?.id ?? "none")",
            "tooltip=\(tooltip ?? "none")",
            "scene-updates=\(views.reduce(0) { $0 + $1.scene.updateCount })",
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
