import AppKit

nonisolated extension SocketCommand {
    /// Facts about the User Guide window: `window`, `title`, `occlusion-visible`, `miniaturized`,
    /// `activation`, `section` (the id on the page), `section-title`, `query`, `visible <ids>`, `sections`
    /// (how many), `duplicate-ids`, `broken-links`, `section-links` (the ids that links to a section name, in order),
    /// `external-links`, `last-link`, `first-responder-is-text`, then one
    /// `section <group>|<id>|<title>|<icon>` line per section, one `block <kind>|<text>` line per block of
    /// the section on the page (a table's rows are joined by ` // `) and one `button <id>|<title>|<tooltip>`
    /// line per button on the page. Test mode only.
    static let userGuideFacts = SocketCommand("user-guide-facts")
    /// `user-guide-fixture <markdown file in the root>|off`: the next User Guide window reads that
    /// file, through the same parser, instead of the bundled guide. Test mode only.
    static let userGuideFixture = SocketCommand("user-guide-fixture")
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
        register(.userGuideFixture) { request in
            guard let argument = request.arguments.first else { return "error user-guide-fixture <markdown file>|off" }
            if argument == "off" {
                UserGuideWindow.fixture = nil
                return "ok"
            }
            guard WindowTesting.isInsideRoot(argument) else { return "error file must be inside the test root" }
            guard let markdown = try? String(contentsOfFile: argument, encoding: .utf8) else { return "error cannot read \(argument)" }
            UserGuideWindow.fixture = GuideDocument(markdown: markdown)
            return "ok"
        }
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
            "section-links=\(sectionLinks(document).joined(separator: ","))",
            "external-links=\(externalLinks(document).joined(separator: ","))",
            "last-link=\(model.lastLink.name)",
            "first-responder-is-text=\(window.firstResponder is NSText)",
        ]
        lines += document.sections.map { "section \($0.group)|\($0.id)|\($0.title)|\($0.icon)" }
        lines += (model.selected?.blocks ?? []).map { "block \($0.kind)|\($0.plainText.replacingOccurrences(of: "\n", with: " // "))" }
        if model.previous != nil {
            lines.append(model.previousButton.factsLine)
        }
        if model.next != nil {
            lines.append(model.nextButton.factsLine)
        }
        return lines.joined(separator: "\n")
    }

    /// The ids that the links to a section name, in document order.
    private static func sectionLinks(_ document: GuideDocument) -> [String] {
        links(document) { link in
            if case .section(let id) = GuideLink(link) { return id }
            return nil
        }
    }

    private static func externalLinks(_ document: GuideDocument) -> [String] {
        links(document) { link in
            if case .external = GuideLink(link) { return link.absoluteString }
            return nil
        }
    }

    /// What `pick` makes of each link of the guide, in document order, for the links it takes.
    private static func links(_ document: GuideDocument, _ pick: (URL) -> String?) -> [String] {
        document.sections.flatMap { $0.blocks.flatMap(\.links) }.compactMap(pick)
    }
}
