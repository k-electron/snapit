/// Check for Updates…, after Settings… (and User Guide) and before the separator that `QuitMenu`
/// brings. Choosing it opens the update window in the Editor helper, which asks GitHub once.
struct CheckForUpdatesMenu: MenuSection {
    var entries: [MenuEntry] {
        [
            .action(id: "check-for-updates", "Check for Updates…") {
                await UpdateWindowLauncher.show()
            }
        ]
    }
}
