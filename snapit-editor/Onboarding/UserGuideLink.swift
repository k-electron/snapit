import Foundation

/// The hook the Done step's User Guide link goes through. The User Guide window sets `open` when
/// it exists; until then the link is not shown.
@MainActor
enum UserGuideLink {
    static var open: (@MainActor () -> Void)?
}
