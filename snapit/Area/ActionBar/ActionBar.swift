import AppKit
import QuartzCore

/// The Action bar's layers: a capsule holding the tiles of `ActionBarRegistry`, left to right. It
/// is hit-tested by the overlay's controller (`control(at:)`), never by AppKit, so every click
/// reaches the overlay's view and a tile's whole rectangle is its hit area. Points are in the
/// bar's own space, with the origin at its top left.
@MainActor
final class ActionBar {
    /// The space between tiles and between the tiles and the capsule's edge.
    static let padding: CGFloat = 6
    static let spacing: CGFloat = 4

    let layer = CALayer()
    let size: CGSize
    private(set) var controls: [ActionBarControl] = []

    init(host: any ActionBarHost, scale: CGFloat) {
        let context = ActionBarContext(host: host, scale: scale)
        controls = ActionBarRegistry.all.map { $0.makeControl(context: context) }
        let width =
            controls.reduce(0) { $0 + $1.preferredSize.width } + Self.spacing * CGFloat(max(0, controls.count - 1))
            + Self.padding * 2
        let height = (controls.map(\.preferredSize.height).max() ?? 0) + Self.padding * 2
        size = CGSize(width: width, height: height)

        layer.bounds = CGRect(origin: .zero, size: size)
        layer.cornerRadius = height / 2
        layer.masksToBounds = true
        // No fill and no edge of its own: the glass behind the tiles (`ActionBarBackdropView`) is the capsule.

        var x = Self.padding
        for control in controls {
            let tile = CGRect(
                x: x, y: Self.padding, width: control.preferredSize.width, height: control.preferredSize.height)
            control.layout(in: tile, barHeight: height)
            layer.addSublayer(control.layer)
            x += tile.width + Self.spacing
        }
    }

    /// The tile under `point`, nil on the capsule's padding.
    func control(at point: CGPoint) -> ActionBarControl? {
        controls.first { $0.frame.contains(point) }
    }

    func control(id: String) -> ActionBarControl? {
        controls.first { $0.id == id }
    }
}
