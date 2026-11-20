import AppKit
import SwiftUI

/// The "Move snapit to Applications" window. It is a helper window like the Editor: it goes
/// through `HelperLifecycle`, and the helper quits when it closes.
@MainActor
final class MoveToApplicationsScreen: NSObject, NSWindowDelegate {
    static var shared: MoveToApplicationsScreen?

    let model: MoveToApplicationsModel
    private(set) var window: NSWindow?

    init(model: MoveToApplicationsModel) {
        self.model = model
        super.init()
        model.onLater = { [weak self] in self?.window?.close() }
    }

    /// Shows the screen, replacing one that is already open.
    static func show(reason: MoveToApplicationsModel.Reason, replacesExisting: Bool) {
        shared?.window?.close()
        let screen = MoveToApplicationsScreen(model: MoveToApplicationsModel(reason: reason, replacesExisting: replacesExisting))
        shared = screen
        screen.show()
    }

    private func show() {
        let hosting = NSHostingView(rootView: MoveToApplicationsView(model: model))
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 460, height: 300)),
            styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = hosting
        window.setContentSize(hosting.fittingSize)
        window.center()
        self.window = window

        HelperLifecycle.windowWillShow()
        window.makeKeyAndOrderFront(nil)
        HelperLifecycle.windowDidShow()
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        if MoveToApplicationsScreen.shared === self { MoveToApplicationsScreen.shared = nil }
    }
}

struct MoveToApplicationsView: View {
    let model: MoveToApplicationsModel

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
            Text(model.title)
                .font(.title2.weight(.semibold))
            Text(model.message)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let note = model.replaceNote {
                Text(note)
                    .foregroundStyle(.secondary)
            }
            status
            HStack(spacing: 10) {
                Button(action: { model.later() }) {
                    label(model.laterButton.title)
                }
                .windowButton(prominent: false)
                .help(model.laterButton.tooltip)
                .keyboardShortcut(.cancelAction)
                .disabled(model.state == .moving)

                Button(action: { Task { _ = await model.move() } }) {
                    label(model.moveButton.title)
                }
                .windowButton(prominent: true)
                .help(model.moveButton.tooltip)
                .keyboardShortcut(.defaultAction)
                .disabled(model.state == .moving)
            }
            .padding(.top, 4)
        }
        .padding(28)
        .frame(width: 460)
        .background(.regularMaterial)
    }

    @ViewBuilder private var status: some View {
        switch model.state {
        case .ready:
            EmptyView()
        case .moving:
            Text("Moving snapit…")
                .foregroundStyle(.secondary)
        case .failed(let message):
            Text(message)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func label(_ title: String) -> some View {
        Text(title)
            .frame(minWidth: 120)
    }
}
