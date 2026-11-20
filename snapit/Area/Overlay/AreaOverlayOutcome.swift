/// Which Capture mode the overlay is for. The Area overlay selects an Area (a drag, or a click on
/// a highlighted window); the window overlay only picks: the window under the pointer is
/// highlighted and a click captures exactly that window. The same panels, frozen frames and
/// layers serve both.
enum AreaOverlayMode: Equatable {
    case area, window
}

/// How the Area overlay ended. `AreaCaptureFlow.finish` turns each outcome into what happens next;
/// a new way out of the overlay (Timed Capture) adds one case here and one arm there.
enum AreaOverlayOutcome: Equatable {
    /// Capture this Area now.
    case capture(AreaSelection)
    /// Capture this Area after a countdown of this many seconds (Timed Capture).
    case timed(AreaSelection, seconds: Int)
    /// Capture this window, and only it (the window overlay's click).
    case window(OnScreenWindow)
    /// Esc, the Cancel button, or the displays changed: nothing is captured.
    case cancel
}
