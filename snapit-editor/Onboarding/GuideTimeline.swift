import CoreGraphics

/// One loop of the Screen Recording guide's animation, as pure functions of its position `t`
/// (0 to 1) in the drawing's own 400 x 240 space.
///
/// The `prompt` loop starts with macOS's message and the cursor choosing Open System Settings;
/// both loops go on with the Screen Recording list: the cursor travels to snapit's switch, turns it
/// on, and chooses Quit & Reopen in the message macOS shows next.
struct GuideTimeline {
    var t: Double
    var variant: PermissionGuideModel.Variant

    // Where things are in the drawing.
    static let size = CGSize(width: 400, height: 240)
    static let promptButton = CGPoint(x: 200, y: 138)
    static let toggle = CGPoint(x: 338, y: 130)
    static let quitAndReopen = CGPoint(x: 252, y: 148)
    private static let promptStart = CGPoint(x: 330, y: 205)
    private static let settingsStart = CGPoint(x: 350, y: 215)

    private func ramp(_ from: Double, _ to: Double) -> Double { min(1, max(0, (t - from) / (to - from))) }
    private func ease(_ x: Double) -> Double { x * x * (3 - 2 * x) }
    private static func lerp(from a: CGPoint, to b: CGPoint, _ x: Double) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * x, y: a.y + (b.y - a.y) * x)
    }

    /// The Screen Recording list's part of the loop, 0 to 1.
    private var u: Double { variant == .prompt ? min(1, max(0, (t - 0.30) / 0.70)) : t }
    private func listRamp(_ from: Double, _ to: Double) -> Double { min(1, max(0, (u - from) / (to - from))) }

    /// macOS's message: shown until the cursor has chosen Open System Settings.
    var promptOpacity: Double { variant == .prompt ? 1 - ramp(0.22, 0.30) : 0 }
    var listOpacity: Double { variant == .prompt ? ramp(0.22, 0.30) : 1 }
    var promptButtonPressed: Bool { variant == .prompt && t >= 0.18 && t < 0.24 }

    /// snapit's switch, 0 (off) to 1 (on).
    var switchOn: Double { ease(listRamp(0.34, 0.44)) }
    /// How far the ring that spreads from the cursor's click on the switch has got; nil when the
    /// cursor is not clicking it.
    var ripple: Double? { (0.30...0.44).contains(u) ? listRamp(0.30, 0.44) : nil }
    /// The "Quit & Reopen" message: appears once the switch is on, fades once it is chosen.
    var quitDialog: Double { ease(listRamp(0.44, 0.52)) * (1 - ease(listRamp(0.86, 0.96))) }
    var quitButtonPressed: Bool { (0.78...0.86).contains(u) }

    var cursorPressed: Bool { promptButtonPressed || (0.30...0.38).contains(u) || quitButtonPressed }

    var cursor: CGPoint {
        let origin =
            variant == .prompt
            ? Self.lerp(from: Self.promptStart, to: Self.promptButton, ease(ramp(0.02, 0.18))) : Self.settingsStart
        let toSwitch = Self.lerp(from: origin, to: Self.toggle, ease(listRamp(0, 0.30)))
        guard u > 0.52 else { return toSwitch }
        return Self.lerp(from: Self.toggle, to: Self.quitAndReopen, ease(listRamp(0.52, 0.78)))
    }
}
