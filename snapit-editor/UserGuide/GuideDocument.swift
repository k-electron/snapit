import Foundation

/// One block of a User Guide section, with inline Markdown (bold, italics, code, links) applied.
/// An image in the text shows as its alternative text: the guide holds no images and fetches none.
enum GuideBlock: Equatable {
    case subheading(AttributedString)
    case paragraph(AttributedString)
    case bullet(AttributedString)
    case numbered(Int, AttributedString)
    case note(AttributedString)
    case table(header: [AttributedString], rows: [[AttributedString]])

    /// The block as plain text, for searching and for the scripted run.
    var plainText: String {
        func text(_ value: AttributedString) -> String { String(value.characters) }
        switch self {
        case .subheading(let value), .paragraph(let value), .bullet(let value), .note(let value): return text(value)
        case .numbered(let number, let value): return "\(number). \(text(value))"
        case .table(let header, let rows):
            return ([header] + rows).map { $0.map(text).joined(separator: " | ") }.joined(separator: "\n")
        }
    }

    /// Every link the block holds.
    var links: [URL] {
        var urls: [URL] = []
        func collect(_ value: AttributedString) { urls += value.runs.compactMap(\.link) }
        switch self {
        case .subheading(let value), .paragraph(let value), .bullet(let value), .note(let value), .numbered(_, let value):
            collect(value)
        case .table(let header, let rows): (header + rows.flatMap { $0 }).forEach(collect)
        }
        return urls
    }
}

/// A section of the User Guide: what the sidebar lists and the page shows. Its `id` is its anchor
/// (`[text](#id)` links to it), written in the guide's source as `## Title {#id icon=symbol.name}`.
struct GuideSection: Equatable, Identifiable {
    let id: String
    let title: String
    let group: String
    /// An SF Symbol name.
    let icon: String
    let blocks: [GuideBlock]

    /// The section's title and text as plain lines.
    var plainText: String {
        ([title] + blocks.map(\.plainText)).joined(separator: "\n")
    }
}

/// The User Guide: groups of sections, parsed from the bundled Markdown (`UserGuide.md`). The
/// Markdown is a small subset: `# Group`, `## Title {#id icon=symbol}` for a section, `###` for a
/// subheading, paragraphs, `- ` bullets, `1. ` steps, `> ` notes and pipe tables. Parsed when the
/// window opens, and gone when it closes.
struct GuideDocument: Equatable {
    let sections: [GuideSection]

    /// The groups in order, each with its sections.
    var groups: [(name: String, sections: [GuideSection])] {
        var result: [(name: String, sections: [GuideSection])] = []
        for section in sections {
            if let last = result.indices.last, result[last].name == section.group {
                result[last].sections.append(section)
            } else {
                result.append((section.group, [section]))
            }
        }
        return result
    }

    func section(id: String) -> GuideSection? { sections.first { $0.id == id } }

    /// Section ids that more than one section has.
    var duplicateIDs: [String] {
        var seen = Set<String>()
        var duplicates: [String] = []
        for section in sections where !seen.insert(section.id).inserted { duplicates.append(section.id) }
        return duplicates
    }

    /// Links to a section that is not there (`#id`), and links that are neither a section nor an
    /// `https` link to GitHub.
    var brokenLinks: [String] {
        var broken: [String] = []
        for link in sections.flatMap({ $0.blocks.flatMap(\.links) }) {
            switch GuideLink(link) {
            case .section(let id): if self.section(id: id) == nil { broken.append(link.absoluteString) }
            case .external: break
            case .refused: broken.append(link.absoluteString)
            }
        }
        return broken
    }

    /// The sections whose title or text holds every word of `query` (any case); all of them for a
    /// blank query.
    func matching(_ query: String) -> [GuideSection] {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return sections }
        return sections.filter { section in
            let text = section.plainText.lowercased()
            return words.allSatisfy { text.contains($0) }
        }
    }

    // MARK: Loading

    /// The guide bundled with the helper. A bundle without it gives a document with one section that
    /// says so, so the window never opens empty.
    static func bundled() -> GuideDocument {
        guard let url = Bundle.main.url(forResource: "UserGuide", withExtension: "md"),
            let markdown = try? String(contentsOf: url, encoding: .utf8)
        else { return missing }
        return GuideDocument(markdown: markdown)
    }

    static let missing = GuideDocument(sections: [
        GuideSection(
            id: "missing", title: "The User Guide could not be loaded", group: "User Guide", icon: "exclamationmark.triangle",
            blocks: [.paragraph(GuideInline.parse("This copy of snapit has no User Guide. Download snapit again."))])
    ])

    init(sections: [GuideSection]) { self.sections = sections }

    init(markdown: String) {
        var sections: [GuideSection] = []
        var group = ""
        var current: (id: String, title: String, icon: String, blocks: [GuideBlock])?
        var table: [[String]] = []

        func finishTable() {
            guard !table.isEmpty else { return }
            let rows = table.filter { !Self.isSeparatorRow($0) }
            table = []
            guard let header = rows.first else { return }
            current?.blocks.append(
                .table(header: header.map(GuideInline.parse), rows: rows.dropFirst().map { $0.map(GuideInline.parse) }))
        }
        func finishSection() {
            finishTable()
            if let current {
                sections.append(
                    GuideSection(id: current.id, title: current.title, group: group, icon: current.icon, blocks: current.blocks))
            }
            current = nil
        }

        for rawLine in markdown.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("|") {
                table.append(Self.cells(of: line))
                continue
            }
            finishTable()
            guard !line.isEmpty else { continue }
            if line.hasPrefix("## ") {
                finishSection()
                let heading = Self.heading(String(line.dropFirst(3)))
                current = (heading.id, heading.title, heading.icon, [])
            } else if line.hasPrefix("# ") {
                finishSection()
                group = String(line.dropFirst(2))
            } else if current != nil {
                if line.hasPrefix("### ") {
                    current?.blocks.append(.subheading(GuideInline.parse(String(line.dropFirst(4)))))
                } else if line.hasPrefix("- ") {
                    current?.blocks.append(.bullet(GuideInline.parse(String(line.dropFirst(2)))))
                } else if line.hasPrefix("> ") {
                    current?.blocks.append(.note(GuideInline.parse(String(line.dropFirst(2)))))
                } else if let step = Self.numberedStep(line) {
                    current?.blocks.append(.numbered(step.number, GuideInline.parse(step.text)))
                } else {
                    current?.blocks.append(.paragraph(GuideInline.parse(line)))
                }
            }
        }
        finishSection()
        self.sections = sections
    }

    /// `Title {#id icon=symbol}`.
    private static func heading(_ text: String) -> (title: String, id: String, icon: String) {
        guard let open = text.range(of: " {#", options: .backwards), text.hasSuffix("}") else {
            return (text, text.lowercased().replacingOccurrences(of: " ", with: "-"), "doc.text")
        }
        let title = String(text[..<open.lowerBound])
        let attributes = text[open.upperBound...].dropLast().split(separator: " ").map(String.init)
        let id = attributes.first ?? title
        let icon = attributes.dropFirst().compactMap { $0.hasPrefix("icon=") ? String($0.dropFirst(5)) : nil }.first
        return (title, id, icon ?? "doc.text")
    }

    private static func numberedStep(_ line: String) -> (number: Int, text: String)? {
        guard let dot = line.firstIndex(of: "."), let number = Int(line[..<dot]), line[line.index(after: dot)...].hasPrefix(" ")
        else { return nil }
        return (number, line[line.index(dot, offsetBy: 2)...].trimmingCharacters(in: .whitespaces))
    }

    private static func cells(of line: String) -> [String] {
        var cells = line.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        if cells.first == "" { cells.removeFirst() }
        if cells.last == "" { cells.removeLast() }
        return cells
    }

    private static func isSeparatorRow(_ cells: [String]) -> Bool {
        !cells.isEmpty && cells.allSatisfy { !$0.isEmpty && $0.allSatisfy { "-: ".contains($0) } }
    }
}

enum GuideInline {
    /// Inline Markdown applied, links kept, images turned into their alternative text.
    static func parse(_ markdown: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnly)
        var text = (try? AttributedString(markdown: markdown, options: options)) ?? AttributedString(markdown)
        for run in text.runs where run.imageURL != nil { text[run.range].imageURL = nil }
        return text
    }
}

/// Where a link in the guide goes.
enum GuideLink: Equatable {
    /// `#id`: another section of the guide, in the same window.
    case section(String)
    /// An `https` link to snapit's own repository on GitHub: opens in the browser, only when clicked.
    case external(URL)
    /// Anything else: dropped.
    case refused

    init(_ url: URL) {
        if url.scheme == nil, url.host == nil, url.path.isEmpty, let fragment = url.fragment, !fragment.isEmpty {
            self = .section(fragment)
        } else if url.scheme?.lowercased() == "https", url.host?.lowercased() == "github.com", url.port == nil, url.user == nil,
            url.path == "/k-electron/snapit" || url.path.hasPrefix("/k-electron/snapit/")
        {
            self = .external(url)
        } else {
            self = .refused
        }
    }
}
