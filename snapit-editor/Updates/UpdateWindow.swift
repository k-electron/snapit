import AppKit
import SwiftUI

/// The update window: "Checking for updates…", then the new version with its release notes and the
/// Update and Relaunch button (and a Release Page link), or one line (up to date, GitHub not reached). One window for the whole
/// helper: asking again while it is open brings it forward. It is a helper window like Settings:
/// it goes through `HelperLifecycle`, and the helper quits when it closes (unless another window
/// is open).
@MainActor
final class UpdateWindow: NSObject, NSWindowDelegate {
    static var shared: UpdateWindow?

    let model = UpdateModel()
    private(set) var window: NSWindow?

    /// Shows the window, or brings the open one forward, and checks (a check already running is
    /// not started again). The only way a check starts.
    static func showAndCheck() {
        let update = shared ?? UpdateWindow()
        shared = update
        update.present()
        update.model.check()
    }

    private func present() {
        if let window {
            HelperLifecycle.windowWillShow()
            window.makeKeyAndOrderFront(nil)
            HelperLifecycle.windowDidShow()
            return
        }
        model.onClose = { [weak self] in self?.window?.close() }
        let controller = NSHostingController(rootView: UpdateView(model: model))
        controller.sizingOptions = [.preferredContentSize]
        let window = NSWindow(contentViewController: controller)
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = model.title
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        self.window = window

        HelperLifecycle.windowWillShow()
        window.makeKeyAndOrderFront(nil)
        HelperLifecycle.windowDidShow()
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        if UpdateWindow.shared === self { UpdateWindow.shared = nil }
    }
}

struct UpdateView: View {
    let model: UpdateModel

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
            Text(model.headline)
                .font(model.notes == nil ? .title3 : .title2.weight(.semibold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let detail = model.detail {
                Text(detail)
                    .foregroundStyle(.secondary)
            }
            if model.notes != nil {
                NotesView(blocks: model.blocks)
            }
            if let reminder = model.reminder {
                Text(reminder)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if model.isInstalling {
                ProgressView()
                    .controlSize(.small)
            }
            HStack(spacing: 10) {
                ForEach(model.buttons, id: \.id) { spec in
                    if spec.id == model.updateButton.id {
                        Button(action: { model.update() }) { label(spec.title) }
                            .windowButton(prominent: true)
                            .help(spec.tooltip)
                            .keyboardShortcut(.defaultAction)
                    } else if spec.id == model.releasePageButton.id {
                        Button(action: { model.openReleasePage() }) {
                            Text(spec.title).frame(minWidth: 70)
                        }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                        .help(spec.tooltip)
                    } else {
                        Button(action: { model.close() }) { label(spec.title) }
                            .windowButton(prominent: false)
                            .help(spec.tooltip)
                            .keyboardShortcut(.cancelAction)
                    }
                }
            }
            .padding(.top, 4)
        }
        .padding(28)
        .frame(width: 480)
        .background(.regularMaterial)
    }

    private func label(_ title: String) -> some View {
        Text(title)
            .frame(minWidth: 110)
    }
}

/// The release notes: headings, bullets and paragraphs, scrolling when they are long. A link in
/// the notes opens in the browser through `BrowserLinks`.
private struct NotesView: View {
    let blocks: [NotesBlock]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    switch block.kind {
                    case .heading:
                        Text(block.attributed).font(.headline).padding(.top, 4)
                    case .bullet:
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("•")
                            Text(block.attributed)
                        }
                    case .paragraph:
                        Text(block.attributed)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .textSelection(.enabled)
        }
        .frame(maxHeight: 240)
        .chromeGlass(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .environment(
            \.openURL,
            OpenURLAction { url in
                BrowserLinks.open(url)
                return .handled
            })
    }
}
