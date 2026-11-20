import AppKit

/// Which displays there are, as far as a frozen frame or a countdown's Area cares: each display's
/// ID, frame and scale.
///
/// macOS posts `NSApplication.didChangeScreenParametersNotification` for more than a display being
/// plugged in, unplugged or rearranged: the Dock growing or shrinking (a different `visibleFrame`),
/// the menu bar, a color profile or an EDR headroom change post it too, and some machines (virtual
/// machines above all) post it now and then with nothing different. The overlay and a Timed
/// Capture's countdown end on a change of displays, and only on one: they remember the
/// configuration they started under and end when the notification arrives and this is no longer
/// the same. A notification with the same displays is left alone.
@MainActor
enum DisplayConfiguration {
    struct Snapshot: Equatable {
        struct Entry: Equatable {
            let id: UInt32
            let frame: CGRect
            let scale: CGFloat
        }

        let entries: [Entry]
        /// How many changes the scripted run has made (`overlay-screens-changed`): the real displays
        /// never move in a run, so a test counts as one by bumping this.
        let simulatedChanges: Int
        /// Not part of what is compared; for the log line only.
        let visibleFrames: [CGRect]

        static func == (lhs: Snapshot, rhs: Snapshot) -> Bool {
            lhs.entries == rhs.entries && lhs.simulatedChanges == rhs.simulatedChanges
        }

        var summary: String {
            let screens = zip(entries, visibleFrames).map {
                "id=\($0.id) frame=\(NSStringFromRect($0.frame)) scale=\($0.scale) visible=\(NSStringFromRect($1))"
            }
            return "[\(screens.joined(separator: "; "))] simulated=\(simulatedChanges)"
        }
    }

    private static var simulatedChanges = 0

    static func current() -> Snapshot {
        let screens = NSScreen.screens
        return Snapshot(
            entries: screens.map {
                let id = ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
                return Snapshot.Entry(id: id, frame: $0.frame, scale: $0.backingScaleFactor)
            },
            simulatedChanges: simulatedChanges,
            visibleFrames: screens.map(\.visibleFrame))
    }

    /// The scripted run's way to change the displays: the next `current()` differs.
    static func simulateChange() { simulatedChanges += 1 }

    /// Called when the notification arrives for `owner` (the overlay or the countdown), which started
    /// under `started`. True when the displays are not what they were. Test mode logs both, so a run's
    /// log says whether a cancel was a change of displays.
    static func changed(since started: Snapshot, for owner: String) -> Bool {
        let now = current()
        let changed = now != started
        if TestMode.isActive {
            NSLog("snapit: displays notification for the \(owner): changed=\(changed) before=\(started.summary) after=\(now.summary)")
        }
        return changed
    }
}
