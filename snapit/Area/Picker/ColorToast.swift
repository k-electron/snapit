import AppKit
import QuartzCore

/// The brief "Copied #RRGGBB" toast after a pick. The overlay has already closed by then, so the
/// toast is a small panel of its own: a Liquid Glass pill with the text in a layer, no activation, no mouse. It fades out after a
/// moment and goes away on a one-shot delay (nothing polls); a second toast replaces the first.
@MainActor
enum ColorToast {
    /// How long the toast stays fully visible, and how long its fade takes.
    static let hold: TimeInterval = 1.2
    static let fade: TimeInterval = 0.3

    private static var panel: NSPanel?
    private static var dismissal: DispatchWorkItem?
    private static var fadeStart: DispatchWorkItem?
    /// The text showing now; nil when there is no toast.
    private(set) static var text: String?
    /// Test mode only: the latest toast's panel, held weakly, to see that it is deallocated once dismissed.
    private(set) static weak var panelForTest: NSPanel?

    /// Shows `text` near the bottom of the display whose frame (AppKit global points) is `frame`.
    static func show(_ text: String, on frame: CGRect, scale: Double) {
        dismiss()
        let label = OverlayLabel(scale: CGFloat(scale))
        label.set(
            text, fontSize: 15, weight: .semibold, color: .white, padX: 18, padY: 9)
        let size = label.size
        label.place(topLeft: .zero, parentHeight: size.height)

        let origin = CGPoint(x: frame.midX - size.width / 2, y: frame.minY + max(24, frame.height * 0.12))
        let panel = NSPanel(
            contentRect: CGRect(origin: origin, size: size), styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.level = .screenSaver
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let content = NSView(frame: CGRect(origin: .zero, size: size))
        content.wantsLayer = true
        content.layer?.addSublayer(label.layer)
        // The pill is Liquid Glass; the text is a layer above it.
        let glass = NSGlassEffectView(frame: CGRect(origin: .zero, size: size))
        glass.style = .regular
        glass.cornerRadius = size.height / 2
        glass.appearance = NSAppearance(named: .darkAqua)
        glass.contentView = content
        panel.contentView = glass
        panel.setFrame(CGRect(origin: origin, size: size), display: false)
        panel.orderFrontRegardless()

        self.panel = panel
        self.text = text
        if TestMode.isActive { panelForTest = panel }
        // One-shot delays: the fade starts after `hold` and the toast goes away when it is over.
        let fading = DispatchWorkItem {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = fade
                panel.animator().alphaValue = 0
            }
        }
        let work = DispatchWorkItem { dismiss() }
        fadeStart = fading
        dismissal = work
        DispatchQueue.main.asyncAfter(deadline: .now() + hold, execute: fading)
        DispatchQueue.main.asyncAfter(deadline: .now() + hold + fade + 0.05, execute: work)
    }

    /// Takes the toast away at once and lets go of its layers.
    static func dismiss() {
        dismissal?.cancel()
        dismissal = nil
        fadeStart?.cancel()
        fadeStart = nil
        text = nil
        guard let panel else { return }
        self.panel = nil
        // The panel, its glass view and its layers are released inside the pool, not at some later
        // turn of the run loop, and what the window server held for them is told to go with the commit.
        autoreleasepool {
            panel.contentView = nil
            panel.orderOut(nil)
            panel.close()
        }
        CATransaction.flush()
    }
}
