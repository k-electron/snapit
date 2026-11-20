import AppKit
import SwiftUI

/// SwiftUI host that acts on the very first click: a click that only focused the window would
/// be lost. A drag on its controls never moves the window.
final class FirstMouseHost<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
}

/// SwiftUI host that refuses the click that merely brings a background Editor forward: it
/// holds Delete Capture, so that click can never delete anything.
final class NoFirstMouseHost<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }
}

/// Holds the text view of a text being typed, over the canvas. It takes no click itself: a click
/// on the canvas under it reaches the canvas, and only the text view is hit.
final class TextHostView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }
}

/// Lays its children out itself and lets a drag on its empty parts move the window.
final class EditorContentView: NSView {
    var onLayout: (() -> Void)?
    override var mouseDownCanMoveWindow: Bool { true }
    override func layout() {
        super.layout()
        onLayout?()
    }
}

/// The Editor window and its furniture: the layer-hosted canvas in the middle, the Annotation
/// tools on the left and the top toolbar, in glass pills that float over the title bar row.
@MainActor
final class EditorChrome {
    static let margin: CGFloat = 12
    static let canvasPadding: CGFloat = 6
    static let baseMinimumContent = NSSize(width: 560, height: 320)
    /// The smallest content size: wide enough that the toolbars' pills never overlap, however many
    /// controls the registry puts in them.
    private(set) var minimumContent = EditorChrome.baseMinimumContent

    let window: EditorWindow
    let canvas: CanvasView
    private let content = EditorContentView(frame: .zero)
    private let rail: NSView
    private let textHost = TextHostView(frame: .zero)
    private let topLeading: NSView?
    /// The content width at which the options pill fits in the title bar row beside the others; below
    /// it, the pill moves to a second row under them.
    private var singleRowWidth: CGFloat = 0
    private let topTrailing: NSView?
    private let topDestructive: NSView?

    init(session: EditorSession) {
        canvas = CanvasView(frame: .zero)
        canvas.padding = Self.canvasPadding
        canvas.session = session
        canvas.textHost = textHost

        func host<V: View>(_ view: V, firstMouse: Bool = true) -> NSView {
            let host: NSHostingView<V> = firstMouse ? FirstMouseHost(rootView: view) : NoFirstMouseHost(rootView: view)
            host.safeAreaRegions = []  // the title bar must not push the toolbars down
            host.layoutSubtreeIfNeeded()
            host.frame.size = host.fittingSize
            return host
        }
        func hostIfAny(_ slots: [ToolbarSlot], firstMouse: Bool = true) -> NSView? {
            slots.contains { !ToolbarRegistry.items(in: $0).isEmpty }
                ? host(ToolbarPillsView(session: session, slots: slots), firstMouse: firstMouse) : nil
        }
        rail = host(ToolRailView(session: session))
        topLeading = hostIfAny([.options])
        topTrailing = hostIfAny([.history, .export])
        topDestructive = hostIfAny([.destructive], firstMouse: false)

        // On one row the pills sit side by side after the traffic lights; narrower than that the
        // options pill takes a second row, right of the tool rail. (The traffic lights take the first
        // 82 points; the pills' shadow margins overlap by 6.)
        let rightWidth = [topTrailing, topDestructive].compactMap { $0?.frame.width }.reduce(0, +)
        let optionsWidth = topLeading?.frame.width ?? 0
        singleRowWidth = 82 + optionsWidth + rightWidth + 6
        minimumContent.width = max(Self.baseMinimumContent.width, 82 + rightWidth + 6, rail.frame.maxX + optionsWidth + Self.margin)
        // The tool rail hangs from the title bar row and must fit whole, whatever the registry holds.
        let barHeight = [topLeading, topTrailing, topDestructive].compactMap { $0?.frame.height }.max() ?? 0
        minimumContent.height = max(Self.baseMinimumContent.height, rail.frame.height + barHeight + Self.margin)

        window = EditorWindow(
            contentRect: NSRect(origin: .zero, size: minimumContent),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.session = session
        window.isReleasedWhenClosed = false
        window.title = "Capture"
        window.allowsToolTipsWhenApplicationIsInactive = true
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = .underPageBackgroundColor
        // An empty toolbar only gives the title bar row its taller, unified height, with the
        // traffic lights centred in it.
        let toolbar = NSToolbar(identifier: "snapit.editor")
        window.toolbar = toolbar
        window.toolbarStyle = .unified
        window.contentMinSize = minimumContent
        window.contentView = content
        for view in [canvas, textHost, rail, topLeading, topTrailing, topDestructive].compactMap({ $0 }) {
            content.addSubview(view)
        }
        content.onLayout = { [weak self] in self?.layoutAll() }
    }

    /// Puts a Capture in the window and sizes the window to fit it. The window, toolbars and
    /// canvas layers already exist (a warming-up helper builds them before any Capture).
    func attach(_ document: EditorDocument) {
        let screen = Self.screenForNewWindow()
        let image = document.capture.pixels.makeCGImage()
        if let image {
            canvas.setCapture(
                image: image, pointSize: document.pointSize, pixels: document.capture.pixels,
                scale: document.capture.info.scale)
        }
        size(for: document.pointSize, on: screen)
    }

    /// The screen under the pointer: where the user is looking when a Capture arrives.
    private static func screenForNewWindow() -> NSScreen {
        let pointer = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    /// Fits the window to the Capture, at most 80% of the screen, and centres it, stepping
    /// diagonally for every other Editor already open.
    private func size(for capture: CGSize, on screen: NSScreen) {
        let visible = screen.visibleFrame
        let rail = self.rail.frame.width
        let top = topTrailing?.frame.height ?? topLeading?.frame.height ?? 62
        let chrome = window.frameRect(forContentRect: NSRect(origin: .zero, size: minimumContent)).size
        let maxWidth = visible.width * 0.8 - (chrome.width - minimumContent.width)
        let maxHeight = visible.height * 0.8 - (chrome.height - minimumContent.height)
        let width = max(minimumContent.width, min(capture.width + rail + Self.margin + 2 * Self.canvasPadding, maxWidth))
        let rows = width < singleRowWidth ? secondRowHeight : 0
        let extraHeight = top + rows + Self.margin + 2 * Self.canvasPadding
        window.setContentSize(
            NSSize(width: width, height: max(minimumContent.height, min(capture.height + extraHeight, maxHeight))))
        // Cascaded: the first diagonal step (28 points down and to the right of the centre) that no
        // other Editor's window already sits on, so closing one in the middle never makes the next
        // one stack on top of another. A step past the screen's edge wraps round to the other side,
        // so big windows (80% of the screen) still get spots of their own.
        let taken = NSApp.windows.filter { $0 is EditorWindow && $0 !== window && $0.isVisible }.map(\.frame.origin)
        let spanX = max(visible.width - window.frame.width, 1)
        let spanY = max(visible.height - window.frame.height, 1)
        func wrapped(_ value: CGFloat, span: CGFloat) -> CGFloat {
            let remainder = value.truncatingRemainder(dividingBy: span)
            return remainder < 0 ? remainder + span : remainder
        }
        func origin(step: Int) -> NSPoint {
            let offset = CGFloat(step) * 28
            let centreX = visible.midX - window.frame.width / 2
            let centreY = visible.midY - window.frame.height / 2
            return NSPoint(
                x: visible.minX + wrapped(centreX + offset - visible.minX, span: spanX),
                y: visible.minY + wrapped(centreY - offset - visible.minY, span: spanY))
        }
        let free = (0..<48).first { step in
            let candidate = origin(step: step)
            return !taken.contains { abs($0.x - candidate.x) < 1 && abs($0.y - candidate.y) < 1 }
        }
        window.setFrameOrigin(origin(step: free ?? 0))
    }

    /// The toolbar's pills hold other controls now (the Crop tool swaps the color and size controls for
    /// Apply and Cancel): once SwiftUI has shown them, the hosts take the size of what they hold. Two
    /// run-loop turns, because the new controls are not there until SwiftUI's own update has run.
    func refitToolbars() {
        func refit() {
            for host in [topLeading, topTrailing, topDestructive].compactMap({ $0 }) {
                host.layoutSubtreeIfNeeded()
                if host.frame.size != host.fittingSize { host.frame.size = host.fittingSize }
            }
            content.needsLayout = true
        }
        DispatchQueue.main.async {
            refit()
            DispatchQueue.main.async { refit() }
        }
    }

    /// How much taller the content must be when the options pill has a row of its own.
    private var secondRowHeight: CGFloat { max(0, (topLeading?.frame.height ?? 0) - 16) }

    /// Positions the toolbars and the canvas for the current content size.
    private func layoutAll() {
        let bounds = content.bounds
        guard bounds.width > 0 else { return }
        var midY = bounds.maxY - 18  // vertical centre of the traffic lights
        var leadX: CGFloat = 92
        if let zoom = window.standardWindowButton(.zoomButton) {
            let frame = content.convert(zoom.convert(zoom.bounds, to: nil), from: nil)
            if frame.height > 0 {
                midY = frame.midY
                leadX = frame.maxX + 8
            }
        }
        let barHeight = [topLeading, topTrailing, topDestructive].compactMap { $0?.frame.height }.max() ?? 0
        let barY = (midY - barHeight / 2).rounded()
        var right = bounds.maxX - 4
        if let destructive = topDestructive {
            right -= destructive.frame.width
            place(destructive, x: right, y: barY)
        }
        if let trailing = topTrailing {
            // The hosts' 10 pt shadow margins overlap, so the pills keep a 10 pt gap.
            right = right + 10 - trailing.frame.width
            place(trailing, x: right, y: barY)
        }
        var canvasTop = barY - 2
        let railTop = min(bounds.maxY - barHeight + 6, barY + 4)
        place(rail, x: 4, y: railTop - rail.frame.height)
        let canvasX = rail.frame.maxX
        if let leading = topLeading {
            if bounds.width >= singleRowWidth {
                place(leading, x: leadX - 10, y: barY)
            } else {
                // A row of its own under the others, level with the canvas's left edge.
                let rowY = barY + 16 - leading.frame.height
                place(leading, x: canvasX - 10, y: rowY)
                canvasTop = rowY + 10 - 2
            }
        }
        let frame = NSRect(
            x: canvasX, y: Self.margin, width: max(1, bounds.width - canvasX - Self.margin),
            height: max(1, canvasTop - Self.margin))
        if canvas.frame != frame { canvas.frame = frame }
        if textHost.frame != frame { textHost.frame = frame }
    }

    private func place(_ view: NSView, x: CGFloat, y: CGFloat) {
        let origin = NSPoint(x: x, y: y)
        if view.frame.origin != origin { view.setFrameOrigin(origin) }
    }

    /// Lets go of the window's views and the Capture's pixels.
    func tearDown() {
        canvas.tearDown()
        window.toolbar = nil
        window.contentView = nil
        window.delegate = nil
        window.session = nil
    }
}
