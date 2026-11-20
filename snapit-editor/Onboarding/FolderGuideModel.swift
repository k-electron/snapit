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
    /// Anything else, with its `errno` when there is one.
    case other

    init(code: Int32?) {
        switch code {
        case EPERM?: self = .privacy
        case EACCES?: self = .notPermitted
        case ENOENT?, ENOTDIR?: self = .missing
        case EROFS?: self = .readOnly
        case ENOSPC?, EDQUOT?: self = .diskFull
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
/// Only the macOS privacy denial has a drawing that plays (System Settings › Files & Folders, with
/// snapit's folder switch turned on) and an "Open System Settings" button; every cause offers
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
        attach(session)
        failures += 1
        animation.stop()
        updateAnimation()
    }

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
    let chooseFolderButton = HelperButton(
        id: "choose-folder", title: "Choose another folder", tooltip: "Choose a different folder for Save")
    let retryButton = HelperButton(
        id: "retry", title: "Try again", tooltip: "Save the Capture again, from the Editor that is still open")
    let replayButton = HelperButton(id: "replay", title: "Replay", tooltip: "Play the animation again")

    var buttons: [HelperButton] {
        var list: [HelperButton] = []
        if cause == .privacy { list.append(openSystemSettingsButton) }
        list.append(chooseFolderButton)
        if canRetry { list.append(retryButton) }
        if cause == .privacy, animation.state == .stopped { list.append(replayButton) }
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
        let start = URL(fileURLWithPath: folder, isDirectory: true).deletingLastPathComponent()
        let existing = FileManager.default.fileExists(atPath: start.path) ? start : SaveLocation.defaultFolder
        SaveLocationChooser.choose(startingAt: existing, from: NSApp.keyWindow) { [weak self] url in
            Task { await self?.useFolder(url) }
        }
    }

    /// Makes `url` the Save location and, when the Editor is still open, saves the Capture there.
    func useFolder(_ url: URL) async {
        SaveLocationChooser.set(url)
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
            situation =
                "macOS is not letting snapit write into \(shortPath). Open System Settings and turn snapit on for this folder under Files & Folders"
                + (canRetry ? ", then choose Try again. Or choose another folder." : ", or choose another folder for the next Save.")
        case .notPermitted:
            situation = "\(shortPath) can't be written to: you don't have permission to add files there."
        case .missing:
            situation = "\(shortPath) can't be written to: the folder is not there any more. Its drive may be unplugged."
        case .readOnly:
            situation = "\(shortPath) can't be written to: it is on a read-only disk."
        case .diskFull:
            situation = "\(shortPath) can't be written to: there is no space left on its disk."
        case .other:
            situation = "\(shortPath) can't be written to" + (code.map { " (error \($0))." } ?? ".")
        }
        if canRetry { return situation + " Your Capture is still open in the Editor, so nothing is lost." }
        return situation + " Your Capture was not saved. If its Editor is still open, Save from it again."
    }

    // MARK: Test mode

    func facts() -> [String] {
        var lines = [
            "guide-folder=\(folder)",
            "guide-code=\(code.map(String.init) ?? "none")",
            "guide-cause=\(cause)",
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
        lines += buttons.map { "button \($0.id)|\($0.title)|\($0.tooltip)" }
        return lines
    }

    // MARK: Animation

    /// Plays while the guide is on screen and the cause is a macOS denial; cancelled the moment it is not.
    private func updateAnimation() {
        if isShown && isVisible && cause == .privacy {
            if animation.state == .idle { animation.play() }
        } else {
            animation.stop()
        }
    }
}
