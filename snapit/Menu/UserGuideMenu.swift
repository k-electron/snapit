/// User Guide, after Settings… and before Check for Updates…. Choosing it asks the Editor helper to
/// show the guide (starting the helper when it is not running).
struct UserGuideMenu: MenuSection {
    var entries: [MenuEntry] {
        [
            .action(id: "user-guide", "User Guide") {
                await HelperWindowLauncher.show(.showUserGuide)
            }
        ]
    }
}
