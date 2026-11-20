import AppKit

// The Editor helper: an agent (no Dock icon) nested in snapit.app/Contents/Helpers.
// Windows switch it to a regular app while they are open; none exist yet.
let application = NSApplication.shared
let delegate = HelperDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
