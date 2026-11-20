import SwiftUI

/// The left toolbar: one button per tool in `ToolRegistry`, in a glass pill.
struct ToolRailView: View {
    let session: EditorSession

    var body: some View {
        GlassGroup {
            VStack(spacing: 4) {
                ForEach(ToolRegistry.all, id: \.id) { tool in
                    Button {
                        session.selectTool(id: tool.id)
                    } label: {
                        Image(systemName: tool.symbol)
                            .font(.system(size: 17, weight: .medium))
                            .frame(width: 40, height: 40)
                    }
                    .buttonStyle(ChromeButtonStyle(look: session.selectedToolID == tool.id ? .selected : .plain, radius: 12))
                    .help(tool.tooltip)
                    .controlMarker(tool.tooltip)
                }
            }
            .padding(6)
            .chromeGlass(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .padding(10)  // room for the glass shadow inside the hosting view
        .fixedSize()
    }
}

/// The items of the given toolbar slots, each slot its own glass pill, side by side.
struct ToolbarPillsView: View {
    let session: EditorSession
    let slots: [ToolbarSlot]

    var body: some View {
        GlassGroup(spacing: 12) {
            HStack(spacing: 10) {
                ForEach(slots, id: \.self) { slot in
                    let items = ToolbarRegistry.items(in: slot).filter { $0.isVisible(in: session) }
                    if !items.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(items, id: \.id) { $0.makeView(session: session) }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .chromeGlass(Capsule())
                    }
                }
            }
        }
        .padding(10)
        .fixedSize()
    }
}
