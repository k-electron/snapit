import AppKit

/// The text view of a Text being typed. Its Cut, Copy and Paste go through `AppPasteboard.current`,
/// never `NSPasteboard.general`, so a scripted run keeps to its private pasteboard.
final class TextEditingView: NSTextView {
    override func copy(_ sender: Any?) {
        guard selectedRange().length > 0 else { return }
        let pasteboard = AppPasteboard.current
        pasteboard.clearContents()
        pasteboard.setString((string as NSString).substring(with: selectedRange()), forType: .string)
    }

    override func cut(_ sender: Any?) {
        guard selectedRange().length > 0 else { return }
        copy(sender)
        deleteBackward(sender)
    }

    override func paste(_ sender: Any?) {
        guard let text = AppPasteboard.current.string(forType: .string) else { return }
        insertText(text, replacementRange: selectedRange())
    }

    override func pasteAsPlainText(_ sender: Any?) { paste(sender) }
}

/// A Text being typed: an `NSTextView` over the canvas, at the text's place and size, until the
/// text is committed (a click away, Esc, another tool, Copy). The committed text is the
/// Annotation's own layer; the text view lives only while it is being edited, so nothing blinks
/// or ticks at rest.
///
/// The text view belongs to a host view beside the canvas, never inside it: the canvas is a
/// layer-hosting view, which cannot hold subviews. Typing goes to the text view, so a tool's key
/// (T, V, R, ...) and ⌫ are characters here, never tool changes or deleted Annotations
/// (`EditorWindow` leaves plain keys to a text being edited).
@MainActor
final class TextEditingController: NSObject, NSTextViewDelegate {
    /// The Annotation being edited: a new one (id 0 until it is committed) or a copy of the
    /// existing one. Its text is what the text view holds when it is committed.
    private(set) var draft: Annotation
    let isNew: Bool
    /// Asks the session to commit (the text view lost the keyboard focus).
    var onEnd: (() -> Void)?
    /// Tells the session the typed text (and so its Undo state) changed.
    var onChange: (() -> Void)?

    // TextKit 1: the text view is made with it, so it never converts from TextKit 2 on first use.
    private let textView = TextEditingView(usingTextLayoutManager: false)
    private let undoer = UndoManager()
    private weak var canvas: CanvasView?
    private weak var host: NSView?

    init(draft: Annotation, isNew: Bool, canvas: CanvasView, host: NSView) {
        self.draft = draft
        self.isNew = isNew
        self.canvas = canvas
        self.host = host
        super.init()
        let view = textView
        view.drawsBackground = false
        view.isRichText = false
        view.importsGraphics = false
        view.allowsUndo = true
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.isAutomaticLinkDetectionEnabled = false
        view.isAutomaticDataDetectionEnabled = false
        view.isContinuousSpellCheckingEnabled = false
        view.isGrammarCheckingEnabled = false
        view.smartInsertDeleteEnabled = false
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = false
        view.textContainer?.containerSize = CGSize(width: 100_000, height: 100_000)
        view.isHorizontallyResizable = true
        view.isVerticallyResizable = true
        view.maxSize = CGSize(width: 100_000, height: 100_000)
        view.delegate = self
        view.string = draft.text
        view.wantsLayer = true
        view.layer?.borderWidth = 1
        view.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.8).cgColor
        applyStyle()
        host.addSubview(view)
        view.window?.makeFirstResponder(view)
        view.setSelectedRange(NSRange(location: (draft.text as NSString).length, length: 0))
        fit()
        undoer.removeAllActions()
    }

    /// What has been typed.
    var text: String { textView.string }

    var canUndo: Bool { undoer.canUndo }
    var canRedo: Bool { undoer.canRedo }
    func undo() { undoer.undo() }
    func redo() { undoer.redo() }

    /// Gives the typed text the new style, at once (the Annotation takes it on commit).
    func restyle(_ change: (inout AnnotationStyle) -> Void) {
        change(&draft.style)
        applyStyle()
        fit()
    }

    private func applyStyle() {
        let color = NSColor(cgColor: draft.style.color.cgColor) ?? .black
        // The font is the Annotation's own size and the lines are as far apart as `TextLayout` sets
        // them; the view's bounds are scaled by the zoom, so what is typed lies where the committed
        // text will.
        let font = NSFont.systemFont(ofSize: draft.style.textSize, weight: .semibold)
        let lines = NSMutableParagraphStyle()
        lines.minimumLineHeight = TextLayout(text: "", fontSize: draft.style.textSize).lineHeight
        lines.maximumLineHeight = lines.minimumLineHeight
        textView.defaultParagraphStyle = lines
        textView.font = font
        textView.textColor = color
        textView.insertionPointColor = color
        textView.typingAttributes = [.font: font, .foregroundColor: color, .paragraphStyle: lines]
        textView.textStorage?.addAttribute(
            .paragraphStyle, value: lines, range: NSRange(location: 0, length: textView.textStorage?.length ?? 0))
    }

    /// Puts the text view where the text is on the canvas (the window or the zoom changed).
    func reposition() {
        applyStyle()
        fit()
    }

    private func fit() {
        guard let canvas, let host, let manager = textView.layoutManager, let container = textView.textContainer else { return }
        manager.ensureLayout(for: container)
        let used = manager.usedRect(for: container)
        let zoom = canvas.zoom
        let width = max(used.width + 6, 40)
        let height = max(used.height, draft.style.textSize * 1.25)
        let top = canvas.convert(canvas.viewPoint(fromImagePoint: draft.start), to: host)
        textView.frame = NSRect(
            x: top.x, y: host.isFlipped ? top.y : top.y - height * zoom, width: width * zoom, height: height * zoom)
        textView.setBoundsSize(NSSize(width: width, height: height))
    }

    /// Lets go of the text: the view is hidden at once and removed one run-loop turn later, because
    /// the commit may come from inside the text view's own key handling (Esc).
    func tearDown() {
        textView.delegate = nil
        onEnd = nil
        onChange = nil
        textView.isHidden = true
        let view = textView
        DispatchQueue.main.async { view.removeFromSuperview() }
    }

    // MARK: NSTextViewDelegate

    func textDidChange(_ notification: Notification) {
        fit()
        onChange?()
    }

    func textDidEndEditing(_ notification: Notification) { onEnd?() }

    /// Esc commits. (It can arrive as `cancelOperation:` or as `complete:`.)
    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.cancelOperation(_:)) || selector == #selector(NSResponder.complete(_:)) {
            onEnd?()
            return true
        }
        return false
    }

    /// The text has its own Undo, apart from the Annotations': ⌘Z takes back typing first.
    func undoManager(for view: NSTextView) -> UndoManager? { undoer }
}
