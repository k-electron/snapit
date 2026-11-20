/// Reopen Last Capture, after the Capture items. Greyed out while there is no Last Capture:
/// `entries` reads `LastCapture.shared`, which is observable, so the menu follows it.
struct LastCaptureMenu: MenuSection {
    var entries: [MenuEntry] {
        [
            .action(id: "reopen-last-capture", "Reopen Last Capture", isEnabled: LastCapture.shared.exists) {
                await ReopenLastCapture.run()
            },
            .separator(id: "last-capture.separator"),
        ]
    }
}
