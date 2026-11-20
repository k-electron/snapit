import SwiftUI

/// The User Guide: a sidebar of sections (with a filter) and the page of the chosen one, drawn
/// natively from the bundled document. Nothing here loads anything: links to other sections
/// navigate in the window and links to GitHub open in the browser when clicked.
struct UserGuideView: View {
    let model: UserGuideModel

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } detail: {
            page
        }
        .environment(\.openURL, OpenURLAction { url in model.follow(url) })
        .frame(minWidth: 640, minHeight: 420)
    }

    // MARK: Sidebar

    private var sidebar: some View {
        List(
            selection: Binding(
                get: { model.selectedID },
                set: { id in if let id { model.select(id) } })
        ) {
            ForEach(model.visibleGroups, id: \.name) { group in
                Section(group.name) {
                    ForEach(group.sections) { section in
                        Label(section.title, systemImage: section.icon)
                            .tag(section.id)
                            .contentShape(Rectangle())
                            .help(model.sidebarTooltip(for: section))
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top, spacing: 0) {
            SearchField(model: model)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .overlay {
            if model.visible.isEmpty {
                Text("No section matches “\(model.query)”.")
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
    }

    // MARK: Page

    @ViewBuilder private var page: some View {
        if let section = model.selected {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(section.title)
                        .font(.largeTitle.weight(.semibold))
                        .padding(.bottom, 4)
                    ForEach(Array(section.blocks.enumerated()), id: \.offset) { _, block in
                        GuideBlockView(block: block)
                    }
                    pager
                        .padding(.top, 16)
                }
                .frame(maxWidth: 680, alignment: .leading)
                .padding(.horizontal, 32)
                .padding(.vertical, 28)
                .frame(maxWidth: .infinity, alignment: .center)
                .textSelection(.enabled)
            }
            .id(section.id)
        } else {
            Text("Choose a section.")
                .foregroundStyle(.secondary)
        }
    }

    private var pager: some View {
        HStack {
            if let previous = model.previous {
                Button { model.goPrevious() } label: {
                    Label(previous.title, systemImage: "chevron.left")
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                }
                .windowButton(prominent: false)
                .help(model.previousButton.tooltip)
            }
            Spacer(minLength: 12)
            if let next = model.next {
                Button { model.goNext() } label: {
                    Label(next.title, systemImage: "chevron.right")
                        .labelStyle(TrailingIconLabelStyle())
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                }
                .windowButton(prominent: false)
                .help(model.nextButton.tooltip)
            }
        }
    }
}

private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.title
            configuration.icon
        }
    }
}

/// The filter above the sidebar: a glass capsule. The clear button's whole circle is its hit area.
private struct SearchField: View {
    let model: UserGuideModel

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(
                model.searchPrompt,
                text: Binding(get: { model.query }, set: { model.search($0) })
            )
            .textFieldStyle(.plain)
            .help(model.searchPrompt)
            if !model.query.isEmpty {
                Button { model.search("") } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(model.clearSearchTooltip)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .glassEffect(in: .capsule)
    }
}

/// One block of a section.
private struct GuideBlockView: View {
    let block: GuideBlock

    var body: some View {
        switch block {
        case .subheading(let text):
            Text(text).font(.title3.weight(.semibold)).padding(.top, 6)
        case .paragraph(let text):
            Text(text).fixedSize(horizontal: false, vertical: true)
        case .bullet(let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•").foregroundStyle(.secondary)
                Text(text).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, 4)
        case .numbered(let number, let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(number).").foregroundStyle(.secondary).monospacedDigit().frame(minWidth: 18, alignment: .trailing)
                Text(text).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, 4)
        case .note(let text):
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "info.circle.fill").foregroundStyle(.tint)
                Text(text).fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        case .table(let header, let rows):
            GuideTable(header: header, rows: rows)
        }
    }
}

private struct GuideTable: View {
    let header: [AttributedString]
    let rows: [[AttributedString]]

    var body: some View {
        Grid(alignment: .topLeading, horizontalSpacing: 18, verticalSpacing: 8) {
            GridRow {
                ForEach(Array(header.enumerated()), id: \.offset) { _, cell in
                    Text(cell).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
            }
            Divider().gridCellUnsizedAxes(.horizontal)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    ForEach(Array(row.enumerated()), id: \.offset) { column, cell in
                        Text(cell)
                            .fontWeight(column == 0 ? .semibold : .regular)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
