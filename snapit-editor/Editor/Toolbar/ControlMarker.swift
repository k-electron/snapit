import AppKit
import SwiftUI

/// Marks where a toolbar control is, so the scripted run can click it. In test mode only, a
/// control gets an invisible AppKit view behind it, the size of the control and named by its
/// tooltip; the run finds it in the window's view tree and sends the mouse events to its centre.
/// Outside test mode the control is returned untouched.
extension View {
    func controlMarker(_ tooltip: String) -> some View {
        modifier(ControlMarkerModifier(tooltip: tooltip))
    }
}

private struct ControlMarkerModifier: ViewModifier {
    let tooltip: String

    @ViewBuilder
    func body(content: Content) -> some View {
        if TestMode.isActive {
            content.background(ControlMarker(tooltip: tooltip))
        } else {
            content
        }
    }
}

/// The marker view: transparent to clicks, so it never takes a click meant for the control.
final class ControlMarkerView: NSView {
    var tooltip = ""
    /// Whether the control the marker sits behind is enabled, as the view shows it.
    var isControlEnabled = true
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private struct ControlMarker: NSViewRepresentable {
    let tooltip: String
    @Environment(\.isEnabled) private var isEnabled

    func makeNSView(context: Context) -> ControlMarkerView {
        let view = ControlMarkerView()
        view.tooltip = tooltip
        view.isControlEnabled = isEnabled
        return view
    }

    func updateNSView(_ view: ControlMarkerView, context: Context) {
        view.tooltip = tooltip
        view.isControlEnabled = isEnabled
    }
}
