import Foundation

/// A release's notes (GitHub's Markdown) as the few blocks the update window draws: headings,
/// bullets and paragraphs, with inline Markdown (bold, italics, code, links) inside each. A line
/// that is none of these is a paragraph, so any text shows, as plain text at worst. Parsed once,
/// when the answer arrives.
struct NotesBlock: Equatable {
    enum Kind: String {
        case heading
        case bullet
        case paragraph
    }

    let kind: Kind
    /// What the block says with inline Markdown applied, links kept, images not: an image shows as
    /// its alternative text and no image is ever fetched.
    let attributed: AttributedString

    /// The same, as plain text.
    var plainText: String { String(attributed.characters) }

    init(kind: Kind, markdown: String) {
        self.kind = kind
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnly)
        var text = (try? AttributedString(markdown: markdown, options: options)) ?? AttributedString(markdown)
        for run in text.runs where run.imageURL != nil { text[run.range].imageURL = nil }
        attributed = text
    }
}

enum ReleaseNotesBlocks {
    static func parse(_ notes: String) -> [NotesBlock] {
        notes.split(whereSeparator: \.isNewline).compactMap { rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { return nil }
            if line.hasPrefix("#") {
                let text = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                if !text.isEmpty { return NotesBlock(kind: .heading, markdown: text) }
            }
            for marker in ["- ", "* ", "+ "] where line.hasPrefix(marker) {
                return NotesBlock(kind: .bullet, markdown: String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces))
            }
            return NotesBlock(kind: .paragraph, markdown: line)
        }
    }
}
