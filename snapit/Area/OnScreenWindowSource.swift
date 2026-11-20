import AppKit
import CoreGraphics

/// A window on screen, for hover-picking.
struct OnScreenWindow {
    /// The window's frame in the global space the window list uses: points, origin at the top
    /// left of the primary display.
    let frame: CGRect
}

/// Where the front-to-back list of on-screen windows comes from. The real source is the window
/// server's list; the scripted run swaps in a fixed list over the fixture display. Always go
/// through `OnScreenWindowSources.current`.
///
/// The list is read once per Capture, when the Shortcut fires, and hover-picking hit-tests that
/// copy: nothing asks the window server per mouse move, and nothing polls.
@MainActor
protocol OnScreenWindowSource {
    /// Ordinary windows of other apps that are on screen, the front one first.
    func windowsFrontToBack() -> [OnScreenWindow]
}

@MainActor
enum OnScreenWindowSources {
    static let current: any OnScreenWindowSource =
        TestMode.isActive ? FixtureWindowSource() : WindowServerWindowSource()
}

/// The window server's list. It carries no window names unless Screen Recording is granted, and
/// asking for it never shows a prompt; only the frames are read here.
struct WindowServerWindowSource: OnScreenWindowSource {
    func windowsFrontToBack() -> [OnScreenWindow] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        let ownProcess = ProcessInfo.processInfo.processIdentifier
        return list.compactMap { info in
            guard
                (info[kCGWindowLayer as String] as? Int) == 0,
                (info[kCGWindowOwnerPID as String] as? Int32) != ownProcess,
                ((info[kCGWindowAlpha as String] as? Double) ?? 1) > 0,
                let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                frame.width >= 8, frame.height >= 8
            else { return nil }
            return OnScreenWindow(frame: frame)
        }
    }
}

/// Test mode's windows: overlapping rectangles over the first fake display, and two that reach
/// out past its edge (into a second display placed to its left or above it, at negative
/// coordinates). The list is the same in every run, so a hover can be aimed at a known window.
///
///     front:  x 60, y 40, 100 x 60 points
///     back:   x 20, y 20, 200 x 130 points
///     left:   x -60, y 30, 80 x 60 points (crosses the first display's left edge)
///     above:  x 100, y -40, 60 x 80 points (crosses the first display's top edge)
struct FixtureWindowSource: OnScreenWindowSource {
    static let front = CGRect(x: 60, y: 40, width: 100, height: 60)
    static let back = CGRect(x: 20, y: 20, width: 200, height: 130)
    static let left = CGRect(x: -60, y: 30, width: 80, height: 60)
    static let above = CGRect(x: 100, y: -40, width: 60, height: 80)

    func windowsFrontToBack() -> [OnScreenWindow] {
        [Self.front, Self.left, Self.above, Self.back].map { OnScreenWindow(frame: $0) }
    }
}
