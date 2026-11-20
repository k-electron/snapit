import Foundation

/// What happens when the user has selected an Area: the Capturing section of Settings.
enum AfterSelectingArea: String, CaseIterable {
    /// The selection stays on screen with eight handles and the Action bar. The default.
    case showActionBar
    /// Letting go of the mouse takes the Capture.
    case captureOnRelease
}

/// The Capturing section of Settings.
enum CapturingSettings {
    static let afterSelectingAreaKey = "afterSelectingArea"

    /// "After selecting an Area". Show Action bar unless Capture on release is stored; any other
    /// stored value counts as the default.
    static var afterSelectingArea: AfterSelectingArea {
        let stored = AppDefaults.store.string(forKey: afterSelectingAreaKey)
        return stored.flatMap(AfterSelectingArea.init(rawValue:)) ?? .showActionBar
    }
}
