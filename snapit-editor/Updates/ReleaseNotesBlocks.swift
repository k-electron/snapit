import Foundation

/// A release's notes (GitHub's Markdown) as the few blocks the update window draws: headings,
/// bullets and paragraphs, with inline Markdown (bold, italics, code, links) inside each. A line
/// that is none of these is a paragraph, so any text shows, as plain text at worst.
enum NotesBlock: Equatable {
    case heading(String)
    case bullet(String)
    case paragraph(String)

    var kind: String {
        switch self {
        case .heading: "heading"
        case .bullet: "bullet"
        case .paragraph: "paragraph"
        }
    }

    /// The Markdown of the block, without its marker.
    var markdown: String {
        switch self {
        case .heading(let text), .bullet(let text), .paragraph(let text): text
        }
    }

    /// What the block says once inline Markdown is applied.
    var plainText: String { String(attributed.characters) }

    var attributed: AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnly)
        return (try? AttributedString(markdown: markdown, options: options)) ?? AttributedString(markdown)
    }
}

enum ReleaseNotesBlocks {
    static func parse(_ notes: String) -> [NotesBlock] {
        notes.split(whereSeparator: \.isNewline).compactMap { rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { return nil }
            if line.hasPrefix("#") {
                let text = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                if !text.isEmpty { return .heading(text) }
            }
            for marker in ["- ", "* ", "+ "] where line.hasPrefix(marker) {
                return .bullet(String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces))
            }
            return .paragraph(line)
        }
    }
}
