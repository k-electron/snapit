import AppKit

/// What the Color picker is pointing at: one device pixel of one display's frozen frame. The
/// pointer aims it (the pixel under the pointer), the arrow keys nudge it by whole device pixels,
/// and it never leaves the frame. A plain value: the overlay's controller owns one while the picker
/// is up.
struct ColorPickerSession: Equatable {
    /// Where the picker was opened from decides what Esc does.
    enum Origin: Equatable {
        /// The Action bar's Pick Color button or its P key: Esc returns to the Action bar.
        case actionBar
        /// The menu item or the Shortcut: Esc ends the overlay.
        case entry
    }

    let origin: Origin
    let enteredAt: ContinuousClock.Instant
    private(set) var displayIndex: Int
    private(set) var pixel: PixelPoint

    /// The picker opens on the pixel under `cursor` (display-local points).
    init(origin: Origin, cursor: CGPoint, displayIndex: Int, scale: Double, width: Int, height: Int) {
        self.origin = origin
        self.displayIndex = displayIndex
        enteredAt = .now
        let under = AreaGeometry.pixel(of: cursor, scale: scale, width: width, height: height)
        pixel = PixelPoint(x: under.x, y: under.y)
    }

    /// Aims at the pixel under `cursor` of display `index`.
    mutating func aim(at cursor: CGPoint, on index: Int, scale: Double, width: Int, height: Int) {
        let under = AreaGeometry.pixel(of: cursor, scale: scale, width: width, height: height)
        displayIndex = index
        pixel = PixelPoint(x: under.x, y: under.y)
    }

    /// Moves the pixel read by whole device pixels, stopping at the frame's edge.
    mutating func nudge(dx: Int, dy: Int, width: Int, height: Int) {
        pixel = PixelPoint(x: max(0, min(width - 1, pixel.x + dx)), y: max(0, min(height - 1, pixel.y + dy)))
    }

    /// The second click of a double-click on the Pick Color button lands here: it is the tail of the
    /// click that opened the picker, not a pick.
    func isTailOfOpeningClick(clickCount: Int) -> Bool {
        clickCount >= 2 && ContinuousClock.now - enteredAt < .seconds(NSEvent.doubleClickInterval)
    }
}

/// What a finished pick hands to the flow: the hex that goes on the pasteboard, and the display it
/// was taken on (the toast shows there).
struct PickedColor: Equatable {
    /// `#RRGGBB`, uppercase.
    let hex: String
    let displayIndex: Int

    /// Copies the hex to the pasteboard, as plain text.
    @MainActor
    func copyToPasteboard() {
        AppPasteboard.write(Data(hex.utf8), as: .string)
    }
}
