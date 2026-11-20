import CoreGraphics
import Foundation

/// The Annotation color, width and fill the user used last, remembered across launches through
/// `AppDefaults.store`. A new Annotation starts with them; choosing a new one in the Editor
/// stores it here. A tool with its own options (Text's size, the Highlighter's width) adds its
/// own keys beside these.
enum AnnotationSettings {
    static let colorKey = "annotationColor"
    static let widthKey = "annotationWidth"
    static let filledKey = "annotationFilled"

    /// The remembered color as `RRGGBB`; red until the user picks another.
    static var color: AnnotationColor {
        get { (AppDefaults.store.string(forKey: colorKey)).flatMap(AnnotationColor.init(hex:)) ?? .red }
        set { AppDefaults.store.set(newValue.hex, forKey: colorKey) }
    }

    /// The remembered line width in points.
    static var width: CGFloat {
        get {
            let stored = AppDefaults.store.object(forKey: widthKey)
            let value = (stored as? Double) ?? (stored as? String).flatMap(Double.init)
            return value.map { CGFloat(min(max($0, 1), 64)) } ?? 5
        }
        set { AppDefaults.store.set(Double(newValue), forKey: widthKey) }
    }

    /// Whether new Rectangles and Ovals are a solid fill rather than an outline.
    static var filled: Bool {
        get { AppSetting.bool(filledKey, default: false) }
        set { AppDefaults.store.set(newValue, forKey: filledKey) }
    }

    /// The style a new Annotation starts with.
    static var style: AnnotationStyle {
        AnnotationStyle(color: color, width: width, filled: filled)
    }
}
