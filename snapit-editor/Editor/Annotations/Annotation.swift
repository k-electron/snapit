import CoreGraphics

/// Which kind of mark an Annotation is: Arrow, Rectangle, Oval, and as tickets add them Text,
/// Highlighter and Redaction. A kind is a name, not a case of an enum, so a feature adds its own
/// (a `static let` in its kind's file) without touching a shared type; `AnnotationKinds` maps
/// the name to what the kind does. An unknown name (a newer snapit wrote it) still decodes.
nonisolated struct AnnotationKindID: RawRepresentable, Codable, Hashable, Sendable {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }
    init(_ rawValue: String) { self.rawValue = rawValue }

    init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// An Annotation color, in sRGB.
nonisolated struct AnnotationColor: Codable, Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double = 1

    var cgColor: CGColor { CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha) }

    /// The default Annotation color.
    static let red = AnnotationColor(red: 1.0, green: 0.23, blue: 0.19)

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// `RRGGBB`, what the settings store.
    var hex: String {
        func part(_ value: Double) -> String {
            let byte = Int((min(max(value, 0), 1) * 255).rounded())
            return (byte < 16 ? "0" : "") + String(byte, radix: 16)
        }
        return part(red) + part(green) + part(blue)
    }

    /// Parses `RRGGBB` (a leading `#` is fine); nil when it is anything else.
    init?(hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255)
    }
}

/// How an Annotation looks. A field added later (a tool's text size, say) gets a default and is
/// decoded with `decodeIfPresent`, so documents written before the field existed still open.
nonisolated struct AnnotationStyle: Codable, Equatable, Sendable {
    var color = AnnotationColor.red
    /// The line width in points.
    var width: CGFloat = 5
    /// Rectangle and Oval: a solid fill in the Annotation color instead of an outline.
    var filled = false

    init(color: AnnotationColor = .red, width: CGFloat = 5, filled: Bool = false) {
        self.color = color
        self.width = width
        self.filled = filled
    }

    private enum CodingKeys: String, CodingKey { case color, width, filled }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        color = try container.decodeIfPresent(AnnotationColor.self, forKey: .color) ?? .red
        width = try container.decodeIfPresent(CGFloat.self, forKey: .width) ?? 5
        filled = try container.decodeIfPresent(Bool.self, forKey: .filled) ?? false
    }
}

/// One mark on a Capture. A value type: Undo restores whole snapshots of the list.
///
/// `start` and `end` are in image points, origin at the top left, the Capture's own coordinates
/// whatever the zoom: an Arrow runs from its tail to its tip, a Rectangle and an Oval from one
/// corner of their box to the opposite one.
nonisolated struct Annotation: Codable, Equatable, Identifiable, Sendable {
    var id: Int
    var kind: AnnotationKindID
    var start: CGPoint
    var end: CGPoint
    var style: AnnotationStyle

    init(id: Int, kind: AnnotationKindID, start: CGPoint, end: CGPoint, style: AnnotationStyle) {
        self.id = id
        self.kind = kind
        self.start = start
        self.end = end
        self.style = style
    }

    private enum CodingKeys: String, CodingKey { case id, kind, start, end, style }

    /// A field added later is decoded with `decodeIfPresent` and a default, like `style`.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        kind = try container.decode(AnnotationKindID.self, forKey: .kind)
        start = try container.decode(CGPoint.self, forKey: .start)
        end = try container.decode(CGPoint.self, forKey: .end)
        style = try container.decodeIfPresent(AnnotationStyle.self, forKey: .style) ?? AnnotationStyle()
    }

    /// The box `start` and `end` span.
    var box: CGRect {
        CGRect(
            x: min(start.x, end.x), y: min(start.y, end.y),
            width: abs(start.x - end.x), height: abs(start.y - end.y))
    }

    /// The same Annotation moved by a distance in image points.
    func moved(by delta: CGSize) -> Annotation {
        var copy = self
        copy.start = CGPoint(x: start.x + delta.width, y: start.y + delta.height)
        copy.end = CGPoint(x: end.x + delta.width, y: end.y + delta.height)
        return copy
    }
}
