import AppKit
import QuartzCore

/// The canvas's Annotation layers: one persistent layer per Annotation, made and updated by its
/// kind, plus the selection's outline and handles. Everything runs inside one transaction with
/// actions off, only for what changed, so a drag costs a path update on one layer and nothing is
/// ever redrawn or animated (0% CPU at rest).
///
/// The layers are in the order Export paints: kinds another stage draws (Redaction) in
/// `effectHost`, beneath `host`, which holds all the others (`AnnotationKinds.paintOrder`).
@MainActor
final class AnnotationLayers {
    private struct Entry {
        let layer: CALayer
        let isEffect: Bool
        var annotation: Annotation
    }

    private let host: CALayer
    private let effectHost: CALayer
    private let selectionHost: CALayer
    private var entries: [Int: Entry] = [:]
    private var effectOrder: [Int] = []
    private var order: [Int] = []
    private let outline = CAShapeLayer()
    private var handleLayers: [CALayer] = []
    private var annotations: [Annotation] = []
    private var selected: Annotation?
    private var zoom: CGFloat = 1
    private var cropPixels: PixelRect?

    private static let accent = CGColor(srgbRed: 0.04, green: 0.52, blue: 1, alpha: 1)

    /// `host` holds the Annotations' layers and `effectHost` those of the kinds drawn beneath
    /// them (both clipped to the Capture); `selectionHost` holds the selection's, above them and
    /// not clipped, so a handle on the Capture's edge shows whole.
    init(host: CALayer, effectHost: CALayer, selectionHost: CALayer) {
        self.host = host
        self.effectHost = effectHost
        self.selectionHost = selectionHost
        outline.fillColor = nil
        outline.strokeColor = Self.accent
        outline.isHidden = true
        selectionHost.addSublayer(outline)
    }

    /// Makes the layers show these Annotations, with `selected` outlined. The context's zoom is
    /// how many view points one image point takes, so the selection's lines and handles keep
    /// their size.
    func show(_ annotations: [Annotation], selected: Annotation?, context: AnnotationRenderContext) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let zoomChanged = context.zoom != zoom || context.cropPixels != cropPixels
        zoom = context.zoom
        cropPixels = context.cropPixels
        self.annotations = annotations
        self.selected = selected

        var live: [Int] = []
        var liveEffects: [Int] = []
        for annotation in AnnotationKinds.paintOrder(annotations) {
            guard let kind = AnnotationKinds.kind(annotation.kind) else { continue }
            let isEffect = !kind.drawnByAnnotationStage
            if isEffect { liveEffects.append(annotation.id) } else { live.append(annotation.id) }
            if var entry = entries[annotation.id] {
                if entry.annotation != annotation || zoomChanged {
                    kind.update(entry.layer, for: annotation, in: context)
                    entry.annotation = annotation
                    entries[annotation.id] = entry
                }
            } else {
                let layer = kind.makeLayer(in: context)
                layer.frame = host.bounds
                kind.update(layer, for: annotation, in: context)
                entries[annotation.id] = Entry(layer: layer, isEffect: isEffect, annotation: annotation)
            }
        }
        let gone = Set(entries.keys).subtracting(live).subtracting(liveEffects)
        for id in gone {
            entries[id]?.layer.removeFromSuperlayer()
            entries[id] = nil
        }
        if live != order || !gone.isEmpty {
            order = live
            host.sublayers = live.compactMap { entries[$0]?.layer }
        }
        if liveEffects != effectOrder || !gone.isEmpty {
            effectOrder = liveEffects
            effectHost.sublayers = liveEffects.compactMap { entries[$0]?.layer }
        }
        layoutSelection()
    }

    /// Hides or shows the layer of an Annotation (a Text hides its own while it is being typed).
    func setHidden(_ hidden: Bool, id: Int) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        entries[id]?.layer.isHidden = hidden
        CATransaction.commit()
    }

    /// A drag ended: layers whose previews were throttled while it lasted catch up now.
    func settle() {
        for entry in entries.values where entry.isEffect {
            (entry.layer as? RedactionPreviewLayer)?.flush()
        }
    }

    /// The canvas's zoom or Capture changed (the window was resized): the layers that depend on
    /// it are updated and the selection is drawn again.
    func contextChanged(_ context: AnnotationRenderContext) {
        guard context.zoom != zoom || context.cropPixels != cropPixels else { return }
        show(annotations, selected: selected, context: context)
    }

    private func layoutSelection() {
        guard let selected, let kind = AnnotationKinds.kind(selected.kind), !kind.bounds(of: selected).isNull else {
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
        effectOrder.removeAll()
        annotations.removeAll()
        selected = nil
        outline.removeFromSuperlayer()
        for handle in handleLayers { handle.removeFromSuperlayer() }
        handleLayers.removeAll()
    }
}
