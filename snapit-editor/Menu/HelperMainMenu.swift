import AppKit

/// The helper's own menus, shown in the menu bar while it is a regular app: snapit (About,
/// Hide, Quit), then one menu per `EditorMenu` (Edit, Window), whose items come from
/// `ToolbarRegistry`. Installed at launch, before the helper first becomes a regular app.
@MainActor
enum HelperMainMenu {
    static func install(quitTarget: AnyObject, quitAction: Selector) {
        let mainMenu = NSMenu()
        mainMenu.addItem(submenuItem(title: "snapit", appMenu(quitTarget: quitTarget, quitAction: quitAction)))
        for menu in EditorMenu.allCases {
            let built = editorMenu(menu)
            if built.items.isEmpty { continue }
            mainMenu.addItem(submenuItem(title: menu.rawValue, built))
            if menu == .window { NSApp.windowsMenu = built }
        }
        NSApp.mainMenu = mainMenu
    }

    private static func submenuItem(title: String, _ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    private static func appMenu(quitTarget: AnyObject, quitAction: Selector) -> NSMenu {
        let menu = NSMenu(title: "snapit")
        menu.addItem(
            withTitle: "About snapit", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Hide snapit", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        menu.addItem(.separator())
        let quit = menu.addItem(withTitle: "Quit snapit", action: quitAction, keyEquivalent: "q")
        quit.target = quitTarget
        return menu
    }

    /// The menu's fixed items, then the registry's items for it, in order.
    private static func editorMenu(_ kind: EditorMenu) -> NSMenu {
        let menu = NSMenu(title: kind.rawValue)
        if kind == .window {
            menu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        }
        for item in ToolbarRegistry.items(in: kind) {
            let menuItem = NSMenuItem(
                title: item.menuTitle, action: #selector(EditorWindow.performToolbarItem(_:)),
                keyEquivalent: item.keyEquivalent?.key ?? "")
            menuItem.keyEquivalentModifierMask = item.keyEquivalent?.modifiers ?? []
            menuItem.representedObject = item.id
            menu.addItem(menuItem)
        }
        return menu
    }
}
