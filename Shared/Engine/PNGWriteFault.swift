import Foundation

/// Test mode's way of making a PNG write fail the way a real one fails (a full disk), at the one
/// place the engine's answer is read (`PixelBuffer.writePNG(toDescriptor:)`): the failure then goes
/// through the real mapping, status and `errno` from the engine's `os_error`, to whatever reports it.
/// Never set outside a scripted run (`save-fail-write`).
nonisolated enum PNGWriteFault {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var osError: Int32?

    /// The `errno` the next writes fail with, or nil for none.
    static var injectedOSError: Int32? {
        get { lock.withLock { osError } }
        set { lock.withLock { osError = newValue } }
    }
}
