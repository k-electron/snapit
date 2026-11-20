import AppKit
import QuartzCore

/// The canvas's Annotation layers: one persistent layer per Annotation, made and updated by its
/// kind, plus the selection's outline and handles. Everything runs inside one transaction with
/// actions off, only for what changed, so a drag costs a path update on one layer and nothing is
/// ever redrawn or animated (0% CPU at rest).
@MainActor
final class AnnotationLayers {
    private struct Entry {
        let layer: CALayer
        var annotation: Annotation
    }

    private let host: CALayer
    private let selectionHost: CALayer
    private var entries: [Int: Entry] = [:]
    private var order: [Int] = []
    private let outline = CAShapeLayer()
    private var handleLayers: [CALayer] = []
    private var selected: Annotation?

    private static let accent = CGColor(srgbRed: 0.04, green: 0.52, blue: 1, alpha: 1)

    /// `host` holds the Annotations' layers (clipped to the Capture); `selectionHost` holds the
    /// selection's, above them and not clipped, so a handle on the Capture's edge shows whole.
    init(host: CALayer, selectionHost: CALayer) {
        self.host = host
        self.selectionHost = selectionHost
        outline.fillColor = nil
        outline.strokeColor = Self.accent
        outline.isHidden = true
        selectionHost.addSublayer(outline)
    }

    /// Makes the layers show these Annotations, with `selected` outlined. `zoom` is how many view
    /// points one image point takes, so the selection's lines and handles keep their size.
    func show(_ annotations: [Annotation], selected: Annotation?, zoom: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        var live: [Int] = []
        for annotation in annotations {
            guard let kind = AnnotationKinds.kind(annotation.kind) else { continue }
            live.append(annotation.id)
            if var entry = entries[annotation.id] {
                if entry.annotation != annotation {
                    kind.update(entry.layer, for: annotation)
                    entry.annotation = annotation
                    entries[annotation.id] = entry
                }
            } else {
                let layer = kind.makeLayer()
                layer.frame = host.bounds
                kind.update(layer, for: annotation)
                entries[annotation.id] = Entry(layer: layer, annotation: annotation)
            }
        }
        let gone = Set(entries.keys).subtracting(live)
        for id in gone {
            entries[id]?.layer.removeFromSuperlayer()
            entries[id] = nil
        }
        if live != order || !gone.isEmpty {
            order = live
            host.sublayers = live.compactMap { entries[$0]?.layer }
        }
        self.selected = selected
        layoutSelection(zoom: zoom)
    }

    /// Redraws the selection for a new zoom (the window was resized).
    func relayoutSelection(zoom: CGFloat) {
        guard selected != nil else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layoutSelection(zoom: zoom)
        CATransaction.commit()
    }

    private func layoutSelection(zoom: CGFloat) {
        guard let selected, let kind = AnnotationKinds.kind(selected.kind) else {
            outline.isHidden = true
            for handle in handleLayers { handle.isHidden = true }
            return
        }
        let zoom = max(zoom, 0.01)
        outline.frame = selectionHost.bounds
        outline.path = CGPath(rect: kind.bounds(of: selected).insetBy(dx: -2 / zoom, dy: -2 / zoom), transform: nil)
        outline.lineWidth = 1 / zoom
        outline.lineDashPattern = [NSNumber(value: 4 / zoom), NSNumber(value: 3 / zoom)]
        outline.isHidden = false

        let points = kind.handles(of: selected)
        let size = 9 / zoom
        while handleLayers.count < points.count {
            let handle = CALayer()
            handle.backgroundColor = CGColor(gray: 1, alpha: 1)
            handle.borderColor = Self.accent
            selectionHost.addSublayer(handle)
            handleLayers.append(handle)
        }
        for (index, handle) in handleLayers.enumerated() {
            guard index < points.count else {
                handle.isHidden = true
                continue
            }
            handle.isHidden = false
            handle.bounds = CGRect(x: 0, y: 0, width: size, height: size)
            handle.position = points[index]
            handle.cornerRadius = 2 / zoom
            handle.borderWidth = 1.5 / zoom
        }
    }

    func tearDown() {
        for entry in entries.values { entry.layer.removeFromSuperlayer() }
        entries.removeAll()
        order.removeAll()
        selected = nil
        outline.removeFromSuperlayer()
        for handle in handleLayers { handle.removeFromSuperlayer() }
        handleLayers.removeAll()
    }
}
