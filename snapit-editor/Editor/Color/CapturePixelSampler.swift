import CoreGraphics

/// Reads one pixel of the Capture as an Annotation color. Only the Capture's own pixels: never
/// an Annotation drawn over them. The pixels are read-only here (the mapping is never written).
nonisolated enum CapturePixelSampler {
    /// The pixel that holds `point` (image points, origin at the top left) when `scale` pixels
    /// make a point; nil outside the Capture. A point is the top left corner of its own pixel at
    /// 2x, so 10.5 points is pixel 21 and 10.49 is pixel 20.
    static func pixel(containing point: CGPoint, scale: Double, in buffer: PixelBuffer) -> (x: Int, y: Int)? {
        let x = Int((point.x * scale).rounded(.down))
        let y = Int((point.y * scale).rounded(.down))
        guard x >= 0, y >= 0, x < buffer.width, y < buffer.height else { return nil }
        return (x, y)
    }

    /// What the canvas shows at pixel (`x`, `y`) of the Capture, as a color: the Capture's own pixel, or
    /// under a Redaction the pixelated value (the topmost Redaction that covers it, made by the engine
    /// as the preview and the Export make it), never the original pixel it hides. `window` is the part
    /// of the Capture a crop kept (nil for all of it).
    static func shownColor(
        atX x: Int, y: Int, in buffer: PixelBuffer, scale: Double, window: PixelRect?, redactions: [Annotation]
    ) -> AnnotationColor? {
        let window = window ?? PixelRect(x: 0, y: 0, width: buffer.width, height: buffer.height)
        for annotation in redactions.reversed() {
            guard
                let geometry = RedactionGeometry(
                    annotation: annotation, scale: scale, captureWidth: buffer.width, captureHeight: buffer.height,
                    window: window)
            else { continue }
            let areaX = x - window.x - geometry.area.x, areaY = y - window.y - geometry.area.y
            guard areaX >= 0, areaY >= 0, areaX < geometry.area.width, areaY < geometry.area.height else { continue }
            // The pixel is under this Redaction: read it from the pixelated area, not the original.
            guard let pixelated = try? buffer.makeEmptyBuffer(width: geometry.area.width, height: geometry.area.height),
                (try? Engine.pixelate(buffer, window: window, area: geometry.area, block: geometry.block, into: pixelated)) != nil
            else { return nil }
            return color(atX: areaX, y: areaY, in: pixelated)
        }
        return color(atX: x, y: y, in: buffer)
    }

    /// The color at pixel (`x`, `y`) in extended sRGB. A Display P3 pixel that sRGB cannot show keeps
    /// its channels beyond 0...1 instead of being clamped, so drawn back into that Capture it comes out
    /// the same.
    static func color(atX x: Int, y: Int, in buffer: PixelBuffer) -> AnnotationColor? {
        guard x >= 0, y >= 0, x < buffer.width, y < buffer.height else { return nil }
        // Pixels are BGRA, 8 bits each, rows `stride` bytes apart.
        let bytes: (b: UInt8, g: UInt8, r: UInt8) = buffer.withReadOnlyPixels { base, stride in
            let pixel = base.advanced(by: y * stride + x * 4).assumingMemoryBound(to: UInt8.self)
            return (pixel[0], pixel[1], pixel[2])
        }
        let components = [CGFloat(bytes.r) / 255, CGFloat(bytes.g) / 255, CGFloat(bytes.b) / 255, 1]
        guard let source = CGColor(colorSpace: buffer.colorSpace, components: components),
            let srgb = CGColorSpace(name: CGColorSpace.extendedSRGB),
            let converted = source.converted(to: srgb, intent: .defaultIntent, options: nil),
            let values = converted.components, values.count >= 3
        else { return nil }
        return AnnotationColor(red: Double(values[0]), green: Double(values[1]), blue: Double(values[2]))
    }
}
