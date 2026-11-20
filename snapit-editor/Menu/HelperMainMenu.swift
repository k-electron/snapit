import AppKit

/// The helper's own menus, shown in the menu bar while it is a regular app: snapit (About,
/// Hide, Quit), Edit (Copy), Window (Minimize, Close). Installed at launch, before the helper
/// first becomes a regular app.
@MainActor
enum HelperMainMenu {
    static func install() {
        let mainMenu = NSMenu()
        mainMenu.addItem(submenuItem(title: "snapit", appMenu()))
        mainMenu.addItem(submenuItem(title: "Edit", editMenu()))
        let windowMenu = windowMenu()
        mainMenu.addItem(submenuItem(title: "Window", windowMenu))
        NSApp.windowsMenu = windowMenu
        NSApp.mainMenu = mainMenu
    }

    private static func submenuItem(title: String, _ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    private static func appMenu() -> NSMenu {
        let menu = NSMenu(title: "snapit")
        menu.addItem(
            withTitle: "About snapit", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Hide snapit", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit snapit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    private static func editMenu() -> NSMenu {
        let menu = NSMenu(title: "Edit")
        menu.addItem(withTitle: "Copy", action: #selector(EditorMenuActions.copyCapture(_:)), keyEquivalent: "c")
        return menu
    }

    private static func windowMenu() -> NSMenu {
        let menu = NSMenu(title: "Window")
        menu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        menu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        return menu
    }
}

/// Menu actions that reach the Editor through the responder chain.
@MainActor
@objc protocol EditorMenuActions {
    func copyCapture(_ sender: Any?)
}

extension EditorWindow: EditorMenuActions {
    @objc func copyCapture(_ sender: Any?) {
        session?.startCopy()
    }
}
