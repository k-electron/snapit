import AppKit
import QuartzCore

/// A line of text on a pill, as a persistent layer. It lays itself out again only when its text
/// or style changes, never on a move.
@MainActor
final class OverlayLabel {
    let layer = CALayer()
    private let text = CATextLayer()
    private var key = ""
    private(set) var size = CGSize.zero

    init(scale: CGFloat) {
        layer.contentsScale = scale
        layer.isHidden = true
        text.contentsScale = scale
        text.isWrapped = false
        text.alignmentMode = .left
        layer.addSublayer(text)
    }

    func set(
        _ string: String, fontSize: CGFloat, weight: NSFont.Weight = .regular, color: NSColor, padX: CGFloat = 0,
        padY: CGFloat = 0, background: NSColor? = nil
    ) {
        layer.backgroundColor = background?.cgColor
        let styleKey = "\(string)|\(fontSize)|\(weight.rawValue)|\(padX)|\(padY)|\(color)|\(background != nil)"
        guard styleKey != key else { return }
        key = styleKey
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: weight)
        let attributed = NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color])
        let measured = attributed.size()
        let width = ceil(measured.width), height = ceil(measured.height)
        size = CGSize(width: width + 2 * padX, height: height + 2 * padY)
        layer.bounds = CGRect(origin: .zero, size: size)
        layer.cornerRadius = background == nil ? 0 : size.height / 2
        text.string = attributed
        text.frame = CGRect(x: padX, y: padY, width: width + 2, height: height)
    }

    /// Puts the label's top-left corner at `origin`, in a parent `parentHeight` tall whose
    /// layers have their origin at the bottom left.
    func place(topLeft origin: CGPoint, parentHeight: CGFloat) {
        layer.isHidden = false
        layer.frame = CGRect(x: origin.x, y: parentHeight - origin.y - size.height, width: size.width, height: size.height)
    }

    func hide() { layer.isHidden = true }
}
