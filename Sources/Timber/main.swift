import AppKit

// Timber entry point. Plain AppKit lifecycle (no SwiftUI App scene)
// so no stray windows open: just the status item, popover, and menu.
let delegate = AppDelegate()
let app = NSApplication.shared
app.delegate = delegate
app.run()
