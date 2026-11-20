import AppKit
import QuartzCore

/// What the Crop tool draws on the canvas: a shade over everything outside the crop rectangle, its
/// border and eight handles. The layers are made once and only their paths and positions change
/// (inside a transaction with actions off), so dragging a handle redraws nothing.
///
/// Everything is in image points, in `host` (the selection layer: flipped, above the Annotations,
/// not clipped, so a handle on the Capture's edge shows whole). Sizes are divided by the zoom so
/// the lines and handles keep their size on screen.
@MainActor
final class CropOverlayLayers {
    private let host: CALayer
    private let shade = CAShapeLayer()
    private let border = CAShapeLayer()
    private var handles: [CropHandle: CALayer] = [:]

    private static let accent = CGColor(srgbRed: 0.04, green: 0.52, blue: 1, alpha: 1)

    init(host: CALayer) {
        self.host = host
        shade.fillRule = .evenOdd
        shade.fillColor = CGColor(gray: 0, alpha: 0.5)
        shade.isHidden = true
        border.fillColor = nil
        border.strokeColor = CGColor(gray: 1, alpha: 1)
        border.isHidden = true
        host.addSublayer(shade)
        host.addSublayer(border)
        for handle in CropHandle.allCases {
            let layer = CALayer()
            layer.backgroundColor = CGColor(gray: 1, alpha: 1)
            layer.borderColor = Self.accent
            layer.isHidden = true
            host.addSublayer(layer)
            handles[handle] = layer
        }
    }

    /// Shows the rectangle (`nil` hides everything). The caller runs this in a transaction with
    /// actions disabled.
    func show(_ rect: CGRect?, imageSize: CGSize, zoom: CGFloat) {
        let zoom = max(zoom, 0.01)
        guard let rect else {
            hide()
            return
        }
        let whole = CGRect(origin: .zero, size: imageSize)
        shade.frame = whole
        let path = CGMutablePath()
        path.addRect(whole)
        path.addRect(rect)
        shade.path = path
        shade.isHidden = false
        border.frame = whole
        border.path = CGPath(rect: rect, transform: nil)
        border.lineWidth = 1 / zoom
        border.isHidden = false
        let size = 10 / zoom
        for (handle, layer) in handles {
            layer.bounds = CGRect(x: 0, y: 0, width: size, height: size)
            layer.position = handle.position(on: rect)
            layer.cornerRadius = 2 / zoom
            layer.borderWidth = 1.5 / zoom
            layer.isHidden = false
        }
    }

    private func hide() {
        shade.isHidden = true
        border.isHidden = true
        for layer in handles.values { layer.isHidden = true }
    }

    func tearDown() {
        shade.removeFromSuperlayer()
        border.removeFromSuperlayer()
        for layer in handles.values { layer.removeFromSuperlayer() }
        handles.removeAll()
    }
}
