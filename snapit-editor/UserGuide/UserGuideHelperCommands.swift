import AppKit

nonisolated extension SocketCommand {
    /// Facts about the User Guide window: `window`, `title`, `occlusion-visible`, `miniaturized`,
    /// `activation`, `section` (the id on the page), `section-title`, `query`, `visible <ids>`, `sections`
    /// (how many), `duplicate-ids`, `broken-links`, `external-links`, `last-link`, then one
    /// `section <group>|<id>|<title>` line per section and one `button <id>|<title>|<tooltip>` line per
    /// button on the page. Test mode only.
    static let userGuideFacts = SocketCommand("user-guide-facts")
    /// `user-guide-text <section id>`: the section's text, one block per line. Test mode only.
    static let userGuideText = SocketCommand("user-guide-text")
    /// `user-guide-select <section id>`: what clicking the section in the sidebar does. Test mode only.
    static let userGuideSelect = SocketCommand("user-guide-select")
    /// `user-guide-search [<text>]`: what typing in the search field does. Test mode only.
    static let userGuideSearch = SocketCommand("user-guide-search")
    /// `user-guide-link <url>`: what clicking a link does (the page's own handler). Test mode only.
    static let userGuideLink = SocketCommand("user-guide-link")
    /// `user-guide-press previous|next`: presses a button at the foot of the page. Test mode only.
    static let userGuidePress = SocketCommand("user-guide-press")
    /// `user-guide-snapshot <png path>`: renders the window's view into the run's root. Test mode only.
    static let userGuideSnapshot = SocketCommand("user-guide-snapshot")
    /// Presses the window's close button. The helper quits when no other window is open, so a reply
    /// may never come: wait for the process to go. Test mode only.
    static let userGuideClose = SocketCommand("user-guide-close")
}

extension SocketCommandRegistry {
    func registerUserGuideHelperCommands() {
        // Set when the helper launches, not when the window opens: Onboarding may show first and its
        // Done step shows the link only while this is set.
        UserGuideLink.open = { UserGuideWindow.show() }

        register(.showUserGuide) { _ in
            UserGuideWindow.show()
            // The window is on screen when the reply goes out, not just ordered front.
            CATransaction.flush()
            return "ok"
        }
        guard TestMode.isActive else { return }
        register(.userGuideFacts) { _ in UserGuideFacts.describe() }
        register(.userGuideText) { request in
            guard let guide = UserGuideWindow.shared, let id = request.arguments.first,
                let section = guide.model.document.section(id: id)
            else { return "error user-guide-text <section id>" }
            return section.plainText
        }
        register(.userGuideSelect) { request in
            guard let guide = UserGuideWindow.shared, let id = request.arguments.first else { return "error no User Guide window" }
            return guide.model.select(id) ? "ok" : "error no section \(id)"
        }
        register(.userGuideSearch) { request in
            guard let guide = UserGuideWindow.shared else { return "error no User Guide window" }
            guide.model.search(request.arguments.first ?? "")
            return "ok"
        }
        register(.userGuideLink) { request in
            guard let guide = UserGuideWindow.shared, let text = request.arguments.first, let url = URL(string: text)
            else { return "error user-guide-link <url>" }
            guide.model.follow(url)
            return guide.model.lastLink.name
        }
        register(.userGuidePress) { request in
            guard let model = UserGuideWindow.shared?.model else { return "error no User Guide window" }
            switch request.arguments.first {
            case "previous" where model.previous != nil: model.goPrevious()
            case "next" where model.next != nil: model.goNext()
            default: return "error no such button now: previous|next"
            }
            return "ok"
        }
        register(.userGuideSnapshot) { request in WindowTesting.snapshot(UserGuideWindow.shared?.window, request.arguments) }
        register(.userGuideClose) { _ in WindowTesting.close(UserGuideWindow.shared?.window) }
    }
}

/// What the scripted run reads of the User Guide window.
@MainActor
enum UserGuideFacts {
    static func describe() -> String {
        guard let guide = UserGuideWindow.shared, let window = guide.window else { return "window=none" }
        let model = guide.model
        let document = model.document
        var lines = WindowTesting.facts(window)
        lines += [
            "section=\(model.selectedID)",
            "section-title=\(model.selected?.title ?? "")",
            "query=\(model.query)",
            "visible=\(model.visible.map(\.id).joined(separator: ","))",
            "sections=\(document.sections.count)",
            "duplicate-ids=\(document.duplicateIDs.joined(separator: ","))",
            "broken-links=\(document.brokenLinks.joined(separator: ","))",
            "external-links=\(externalLinks(document).joined(separator: ","))",
            "last-link=\(model.lastLink.name)",
        ]
        lines += document.sections.map { "section \($0.group)|\($0.id)|\($0.title)" }
        if model.previous != nil {
            lines.append("button \(model.previousButton.id)|\(model.previousButton.title)|\(model.previousButton.tooltip)")
        }
        if model.next != nil {
            lines.append("button \(model.nextButton.id)|\(model.nextButton.title)|\(model.nextButton.tooltip)")
        }
        return lines.joined(separator: "\n")
    }

    private static func externalLinks(_ document: GuideDocument) -> [String] {
        document.sections.flatMap { $0.blocks.flatMap(\.links) }.compactMap { link in
            if case .external = GuideLink(link) { return link.absoluteString }
            return nil
        }
    }
}
