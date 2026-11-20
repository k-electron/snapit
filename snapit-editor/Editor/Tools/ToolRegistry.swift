/// Every Annotation tool, on the Editor's left toolbar. A feature adds its tool to `all` with
/// one line; position comes from each tool's `order`, so the line order never matters.
@MainActor
enum ToolRegistry {
    static let all: [any EditorTool] = {
        let tools: [any EditorTool] = [
            SelectTool(),
            ArrowTool(),
            RectangleTool(),
            OvalTool(),
        ]
        return tools.sorted { $0.order < $1.order }
    }()

    static func tool(id: String) -> (any EditorTool)? {
        all.first { $0.id == id }
    }

    static func tool(forKey key: Character) -> (any EditorTool)? {
        all.first { $0.key?.lowercased() == key.lowercased() }
    }

    /// The tool the Editor starts with.
    static var initial: any EditorTool { all[0] }
}
