import Foundation

/// The hook the Done step's User Guide link goes through. The User Guide sets `open` when the helper
/// launches (in `registerHelperCommands`), not when its window opens: Onboarding may show first. Until
/// it is set the link is not shown.
@MainActor
enum UserGuideLink {
    static var open: (@MainActor () -> Void)?
}
