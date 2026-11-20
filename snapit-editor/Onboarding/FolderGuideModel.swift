import AppKit
import Darwin
import Observation
import SwiftUI

/// Why a write into the Save location failed, as far as the user needs to tell causes apart. Only a
/// macOS privacy denial (`EPERM`) is about macOS access: the others say the folder can't be written
/// and why.
enum FolderCause: Equatable {
    /// `EPERM`: macOS privacy (TCC) refused snapit the folder, for example "Don't Allow" to the
    /// Documents or Desktop prompt.
    case privacy
    /// `EACCES`: ordinary file permissions refuse it.
    case notPermitted
    /// `ENOENT`: the folder is gone (an unplugged drive, a deleted folder).
    case missing
    /// `EROFS`: a read-only volume.
    case readOnly
    /// `ENOSPC`: a full disk, after the Save was handed over.
    case diskFull
    /// Anything else, worded with the system's own text for its `errno` (a quota, an I/O error), or none.
    case other

    init(code: Int32?) {
        switch code {
        case EPERM?: self = .privacy
        case EACCES?: self = .notPermitted
        case ENOENT?, ENOTDIR?: self = .missing
        case EROFS?: self = .readOnly
        case ENOSPC?: self = .diskFull
        default: self = .other
        }
    }
}

/// The folder Permission guide: shown when a write into the Save location fails. From an Editor
/// (`session` set) the Capture is still open: the guide offers "Try again" and choosing another
/// folder saves it there at once. After the hand-over (no `session`: the Editor that asked may be
/// gone) there is nothing to save again, so it says the Capture was not saved and offers only
/// "Choose another folder", for the next Save.
///
/// Only a macOS privacy denial of a folder that has a Files & Folders switch (`FolderCategory`) has a
/// drawing that plays (System Settings › Files & Folders, with that switch turned on) and an "Open
/// System Settings" button; every cause offers
/// "Choose another folder". The animation is finite and plays only while the window is visible, as
/// the Screen Recording guide's does. Nothing is looked at on a timer or when the window becomes
/// active: the user presses "Try again" when the folder is open.
@MainActor
@Observable
final class FolderGuideModel: GuideContent {
    let kind = PermissionGuideKind.folder
    let animation = GuideAnimation()

    private(set) var folder: String
    private(set) var code: Int32?
    private(set) var cause: FolderCause
    /// The Files & Folders switch macOS keeps for the folder; nil when it has none (see `FolderCategory`).
    private(set) var category: FolderCategory?
    private(set) var isRetrying = false
    /// The Editor whose Save failed; nil after the hand-over.
    @ObservationIgnored private weak var session: EditorSession?
    /// How many times the guide has been given a failure.
    private(set) var failures = 1

    var isShown = false { didSet { updateAnimation() } }
    var isVisible = false { didSet { updateAnimation() } }
    @ObservationIgnored var onFinished: (() -> Void)?

    init(folder: String, code: Int32?, session: EditorSession?) {
        self.folder = folder
        self.code = code
        cause = FolderCause(code: code)
        category = FolderCategory.of(path: folder)
        attach(session)
    }

    private func attach(_ session: EditorSession?) {
        self.session = session
    }

    /// A Save failed again (the retry, or another Editor's): the open guide says the new reason.
    func update(folder: String, code: Int32?, session: EditorSession?) {
        self.folder = folder
        self.code = code
        cause = FolderCause(code: code)
        category = FolderCategory.of(path: folder)
        attach(session)
        failures += 1
        animation.stop()
        updateAnimation()
    }

    /// A macOS privacy denial of a folder that has a switch to turn on: the drawing and Open System Settings
    /// are for this one. An `EPERM` for a folder with none (locked, system-protected, outside the
    /// categories) says macOS is refusing, and offers another folder.
    var showsSettingsSwitch: Bool { cause == .privacy && category != nil }

    var isResolved: Bool { false }
    var windowTitle: String { "Save location" }
    var closeTooltip: String { "Close this window" + (canRetry ? "; the Capture stays open in its Editor" : "") }
    func windowBecameActive() async {}
    func windowResigned() {}

    /// The Editor can still Save: it is open and nothing is exporting.
    var canRetry: Bool {
        guard let session, !session.isClosing, session.window != nil, session.document != nil else { return false }
        return true
    }

    private var folderName: String {
        let name = URL(fileURLWithPath: folder).lastPathComponent
        return name.isEmpty ? folder : name
    }

    private var shortPath: String { (folder as NSString).abbreviatingWithTildeInPath }

    // MARK: Buttons

    let openSystemSettingsButton = HelperButton(
        id: "open-system-settings", title: "Open System Settings",
        tooltip: "Open System Settings at Privacy & Security › Files & Folders")
    static let chooseFolderID = "choose-folder"
    let chooseFolderButton = HelperButton(
        id: FolderGuideModel.chooseFolderID, title: "Choose another folder", tooltip: "Choose a different folder for Save")
    let retryButton = HelperButton(
        id: "retry", title: "Try again", tooltip: "Save the Capture again, from the Editor that is still open")
    let replayButton = HelperButton(id: "replay", title: "Replay", tooltip: "Play the animation again")

    var buttons: [HelperButton] {
        var list: [HelperButton] = []
        if showsSettingsSwitch { list.append(openSystemSettingsButton) }
        list.append(chooseFolderButton)
        if canRetry { list.append(retryButton) }
        if showsSettingsSwitch, animation.state == .stopped { list.append(replayButton) }
        return list
    }

    func press(_ id: String) async -> Bool {
        switch id {
        case openSystemSettingsButton.id: SystemSettingsLinks.open(.filesAndFolders)
        case chooseFolderButton.id: chooseFolder()
        case retryButton.id: await retry()
        case replayButton.id: if animation.state == .stopped { animation.play() }
        default: return false
        }
        return true
    }

    /// Shows the folder chooser (a sheet of the guide's window).
    func chooseFolder() {
        // The panel picks where to start: looking at the folder that was refused from here could be a
        // second access to it, and a prompt of the helper's own.
        SaveLocationChooser.choose(startingAt: nil, from: NSApp.keyWindow) { [weak self] url in
            Task { await self?.useFolder(url) }
        }
    }

    /// Makes `url` the Save location and, when the Editor is still open, saves the Capture there.
    func useFolder(_ url: URL) async {
        SaveLocationChooser.set(url)
        // Nothing to save again (the Capture was handed over, or its Editor is gone): the choice is all
        // there is to do, so the guide has finished.
        guard canRetry else {
            onFinished?()
            return
        }
        await retry()
    }

    /// Saves again from the Editor that is still open. A Save that goes through closes the guide
    /// (`FolderGuide` sees it hand over); one that fails again reaches `update` through
    /// `SaveFailureSignal`, with the new reason.
    func retry() async {
        guard canRetry, !isRetrying, let session else { return }
        isRetrying = true
        session.startSave()
        await session.copyTask?.value
        isRetrying = false
    }

    /// The guide is about a Save from this Editor.
    func isAbout(_ editor: EditorSession) -> Bool { session === editor }

    // MARK: Words

    var headline: String {
        switch cause {
        case .privacy: "snapit can't save into “\(folderName)”"
        case .diskFull: "The disk is full"
        default: canRetry ? "snapit can't save into “\(folderName)”" : "snapit could not finish saving"
        }
    }

    var message: String {
        let situation: String
        switch cause {
        case .privacy:
            if let category {
                situation =
                    "macOS is not letting snapit write into \(shortPath). Open System Settings and turn snapit on for “\(category.title)” under Files & Folders"
                    + (canRetry ? ", then choose Try again. Or choose another folder." : ", or choose another folder for the next Save.")
            } else {
                situation = "macOS is not letting snapit write into \(shortPath). Choose another folder."
            }
        case .notPermitted:
            situation = "\(shortPath) can't be written to: you don't have permission to add files there."
        case .missing:
            situation = "\(shortPath) can't be written to: the folder is not there any more. Its drive may be unplugged."
        case .readOnly:
            situation = "\(shortPath) can't be written to: it is on a read-only disk."
        case .diskFull:
            situation = "\(shortPath) can't be written to: there is no space left on its disk."
        case .other:
            situation = "\(shortPath) can't be written to" + (reason.map { ": \($0)." } ?? ".")
        }
        if canRetry { return situation + " Your Capture is still open in the Editor, so nothing is lost." }
        return situation + " Your Capture was not saved. If its Editor is still open, Save from it again."
    }

    /// The system's own words for the `errno`, as a lowercase phrase ("input/output error"); nil without one.
    private var reason: String? {
        guard let code, let text = strerror(code) else { return nil }
        let phrase = String(cString: text)
        return phrase.prefix(1).lowercased() + phrase.dropFirst()
    }

    // MARK: Test mode

    func facts() -> [String] {
        var lines = [
            "guide-folder=\(folder)",
            "guide-code=\(code.map(String.init) ?? "none")",
            "guide-cause=\(cause)",
            "guide-category=\(category?.title ?? "none")",
            "guide-failures=\(failures)",
            "guide-retry=\(canRetry ? "available" : "unavailable")",
            "guide-retrying=\(isRetrying ? "yes" : "no")",
            "guide-animation=\(animation.state.rawValue)",
            "guide-loops=\(GuideAnimation.loops)",
            "guide-loop-seconds=\(Int(GuideAnimation.loopSeconds))",
            "guide-plays=\(animation.plays)",
            "guide-headline=\(headline)",
            "guide-message=\(message)",
        ]
        lines += buttons.map(\.factsLine)
        return lines
    }

    // MARK: Animation

    /// Plays while the guide is on screen and the cause is a macOS denial; cancelled the moment it is not.
    private func updateAnimation() {
        if isShown && isVisible && showsSettingsSwitch {
            if animation.state == .idle { animation.play() }
        } else {
            animation.stop()
        }
    }
}
