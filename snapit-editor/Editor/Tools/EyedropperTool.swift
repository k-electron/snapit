import AppKit

/// The eyedropper: not one of the tools on the left toolbar but a mode the top toolbar's
/// eyedropper button turns on. While it is on, the next click inside the Capture takes the color
/// of the pixel under the cursor's hot spot as the Annotation color; Esc or another tool ends it.
struct EyedropperTool: EditorTool {
    let id = "eyedropper"
    let order = 0
    let title = "Eyedropper"
    let symbol = "eyedropper"
    var cursor: NSCursor { EyedropperCursor.shared }

    func pointerDown(at point: CGPoint, in session: EditorSession) {
        session.pickColor(at: point)
    }
}

/// The eyedropper's cursor: the eyedropper symbol with its hot spot at the tip, the point that
/// samples a pixel.
enum EyedropperCursor {
    @MainActor static let shared: NSCursor = {
        let size = NSSize(width: 24, height: 24)
        let symbol = NSImage(systemSymbolName: "eyedropper", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 20, weight: .semibold))
        let image = NSImage(size: size, flipped: false) { rect in
            guard let symbol else { return false }
            // A white halo (the symbol drawn offset all round), then the black symbol, so it shows on any Capture.
            for (dx, dy) in [(-1.0, 0.0), (1.0, 0.0), (0.0, -1.0), (0.0, 1.0)] {
                symbol.tinted(.white).draw(in: rect.offsetBy(dx: dx, dy: dy))
            }
            symbol.tinted(.black).draw(in: rect)
            return true
        }
        // The symbol's tip is its bottom left corner; the image is not flipped, so that is
        // (0, height) from the top left.
        return NSCursor(image: image, hotSpot: NSPoint(x: 2, y: size.height - 2))
    }()
}

private extension NSImage {
    func tinted(_ color: NSColor) -> NSImage {
        let copy = NSImage(size: size, flipped: false) { rect in
            self.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        return copy
    }
}
