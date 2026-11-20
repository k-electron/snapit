import Observation
import SwiftUI

/// What the User Guide window shows and does: the document, the section on the page and the
/// search. The view, the window and the scripted run's commands all read this one model, so every
/// word of chrome (a tooltip, a button) is written once.
@MainActor
@Observable
final class UserGuideModel {
    /// What became of the last link that was followed (the scripted run reads it).
    enum LinkOutcome: Equatable {
        case none
        case section(String)
        case browser(URL)
        case refused(String)

        var name: String {
            switch self {
            case .none: "none"
            case .section(let id): "section \(id)"
            case .browser(let url): "browser \(url.absoluteString)"
            case .refused(let text): "refused \(text)"
            }
        }
    }

    let document: GuideDocument
    private(set) var selectedID: String
    private(set) var query = ""
    private(set) var lastLink = LinkOutcome.none

    init(document: GuideDocument = .bundled()) {
        self.document = document
        selectedID = document.sections.first?.id ?? ""
    }

    var selected: GuideSection? { document.section(id: selectedID) }

    /// The sections the sidebar lists: all of them, or those matching the search.
    var visible: [GuideSection] { document.matching(query) }

    /// The sidebar's groups, with only the visible sections.
    var visibleGroups: [(name: String, sections: [GuideSection])] {
        let ids = Set(visible.map(\.id))
        return document.groups.compactMap { group in
            let kept = group.sections.filter { ids.contains($0.id) }
            return kept.isEmpty ? nil : (group.name, kept)
        }
    }

    // MARK: Moving

    /// Shows a section. Returns whether there is one with that id.
    @discardableResult
    func select(_ id: String) -> Bool {
        guard document.section(id: id) != nil else { return false }
        selectedID = id
        return true
    }

    func search(_ text: String) {
        query = text
        // A search that finds sections shows the first one, unless the page already shows one of them.
        if let first = visible.first, !visible.contains(where: { $0.id == selectedID }) { selectedID = first.id }
    }

    private var position: Int? { document.sections.firstIndex { $0.id == selectedID } }
    var previous: GuideSection? { position.flatMap { $0 > 0 ? document.sections[$0 - 1] : nil } }
    var next: GuideSection? { position.flatMap { $0 + 1 < document.sections.count ? document.sections[$0 + 1] : nil } }

    func goPrevious() { if let previous { selectedID = previous.id } }
    func goNext() { if let next { selectedID = next.id } }

    // MARK: Links

    /// The one place a link in the guide goes through, for a click and for the scripted run: a
    /// section link shows that section, a link to GitHub opens in the browser (only because it was
    /// clicked), and anything else is dropped.
    @discardableResult
    func follow(_ url: URL) -> OpenURLAction.Result {
        switch GuideLink(url) {
        case .section(let id):
            if select(id) {
                lastLink = .section(id)
            } else {
                lastLink = .refused(url.absoluteString)
            }
        case .external(let target):
            lastLink = BrowserLinks.open(target) ? .browser(target) : .refused(url.absoluteString)
        case .refused:
            lastLink = .refused(url.absoluteString)
        }
        return .handled
    }

    // MARK: Words

    let windowTitle = "User Guide"
    let searchPrompt = "Search the User Guide"
    let clearSearchTooltip = "Clear the search"
    let previousButton = HelperButton(id: "previous", title: "Previous", tooltip: "Go to the previous section")
    let nextButton = HelperButton(id: "next", title: "Next", tooltip: "Go to the next section")

    func sidebarTooltip(for section: GuideSection) -> String { "Show \(section.title)" }
}
