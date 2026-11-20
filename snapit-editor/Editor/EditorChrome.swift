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
    static let minimumContent = NSSize(width: 560, height: 320)

    let window: EditorWindow
    let canvas: CanvasView
    private let content = EditorContentView(frame: .zero)
    private let rail: NSView
    private let topLeading: NSView?
    private let topTrailing: NSView?
    private let topDestructive: NSView?

    init(session: EditorSession) {
        let screen = Self.screenForNewWindow()
        let image = session.document.capture.pixels.makeCGImage()
        canvas = CanvasView(
            image: image ?? Self.blankImage, pointSize: session.document.pointSize,
            backingScale: screen.backingScaleFactor)
        canvas.padding = Self.canvasPadding
        canvas.session = session

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

        window = EditorWindow(
            contentRect: NSRect(origin: .zero, size: Self.minimumContent),
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
        window.contentMinSize = Self.minimumContent
        window.contentView = content
        for view in [canvas, rail, topLeading, topTrailing, topDestructive].compactMap({ $0 }) {
            content.addSubview(view)
        }
        content.onLayout = { [weak self] in self?.layoutAll() }

        size(for: session.document.pointSize, on: screen)
    }

    private static var blankImage: CGImage {
        CGContext(
            data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)!
            .makeImage()!
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
        let extra = NSSize(
            width: rail + Self.margin + 2 * Self.canvasPadding, height: top + Self.margin + 2 * Self.canvasPadding)
        let chrome = window.frameRect(forContentRect: NSRect(origin: .zero, size: Self.minimumContent)).size
        let maxWidth = visible.width * 0.8 - (chrome.width - Self.minimumContent.width)
        let maxHeight = visible.height * 0.8 - (chrome.height - Self.minimumContent.height)
        window.setContentSize(
            NSSize(
                width: max(Self.minimumContent.width, min(capture.width + extra.width, maxWidth)),
                height: max(Self.minimumContent.height, min(capture.height + extra.height, maxHeight))))
        let others = NSApp.windows.filter { $0 is EditorWindow && $0.isVisible }.count
        let step = CGFloat(others % 12) * 28
        var origin = NSPoint(
            x: visible.midX - window.frame.width / 2 + step, y: visible.midY - window.frame.height / 2 - step)
        origin.x = max(visible.minX, min(visible.maxX - window.frame.width, origin.x))
        origin.y = max(visible.minY, min(visible.maxY - window.frame.height, origin.y))
        window.setFrameOrigin(origin)
    }

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
        if let leading = topLeading { place(leading, x: leadX - 10, y: barY) }

        let railTop = min(bounds.maxY - barHeight + 6, barY + 4)
        place(rail, x: 4, y: railTop - rail.frame.height)
        let canvasX = rail.frame.maxX
        let canvasTop = barY - 2
        let frame = NSRect(
            x: canvasX, y: Self.margin, width: max(1, bounds.width - canvasX - Self.margin),
            height: max(1, canvasTop - Self.margin))
        if canvas.frame != frame { canvas.frame = frame }
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
