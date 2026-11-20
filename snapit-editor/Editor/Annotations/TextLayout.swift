import AppKit
import CoreText

/// How a Text Annotation's lines are set: the one place that knows the font, the line height and
/// where each baseline goes. The canvas's preview layer, the exact hit test, the selection box and
/// the Export all use it, so what is drawn is what is measured. Core Text draws the lines.
///
/// Everything is in image points, origin at the top left, y growing down (the Export's context is
/// flipped to match), so the text matrix is flipped: Core Text draws upright into a y-down context.
nonisolated struct TextLayout {
    let lines: [CTLine]
    /// Distance between baselines.
    let lineHeight: CGFloat
    /// From the top of a line to its baseline.
    let ascent: CGFloat
    /// The box the lines fill, starting at (0, 0).
    let size: CGSize

    init(text: String, fontSize: CGFloat) {
        let font = Self.font(size: fontSize)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
        ]
        let parts = text.components(separatedBy: "\n")
        lines = parts.map { CTLineCreateWithAttributedString(NSAttributedString(string: $0, attributes: attributes)) }
        ascent = CTFontGetAscent(font)
        lineHeight = ascent + CTFontGetDescent(font) + CTFontGetLeading(font)
        let width = lines.map { CTLineGetTypographicBounds($0, nil, nil, nil) }.max() ?? 0
        size = CGSize(width: max(CGFloat(width), 1), height: lineHeight * CGFloat(lines.count))
    }

    /// The Text font: the system font, semibold, so it reads over any Capture.
    static func font(size: CGFloat) -> CTFont {
        NSFont.systemFont(ofSize: size, weight: .semibold) as CTFont
    }

    /// Draws the lines with the top left of the first at `origin`, in the context's current fill
    /// color, in a context whose y axis grows down.
    func draw(at origin: CGPoint, in context: CGContext) {
        context.saveGState()
        defer { context.restoreGState() }
        // The same glyph rendering in every context (the canvas's layer, the Export's buffer): grayscale
        // anti-aliasing with no stem darkening, glyphs at exact fractional positions.
        context.setShouldAntialias(true)
        context.setAllowsFontSmoothing(false)
        context.setShouldSmoothFonts(false)
        context.setAllowsFontSubpixelPositioning(true)
        context.setShouldSubpixelPositionFonts(true)
        context.setAllowsFontSubpixelQuantization(false)
        context.setShouldSubpixelQuantizeFonts(false)
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        for (index, line) in lines.enumerated() {
            context.textPosition = CGPoint(x: origin.x, y: origin.y + CGFloat(index) * lineHeight + ascent)
            CTLineDraw(line, context)
        }
    }
}
