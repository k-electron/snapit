import AppKit

// The Editor helper: an agent (no Dock icon) nested in snapit.app/Contents/Helpers.
// It becomes a regular app while it has a window open.
let application = NSApplication.shared
let delegate = HelperDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
