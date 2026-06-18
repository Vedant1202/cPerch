import AppKit
import CPerchCore

// cPerch — menu-bar agent (LSUIElement / no Dock icon).
// P0 walking skeleton: a Claude-colored status dot driven by the stub store.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let store = StubSessionStore()
let controller = MenuBarController(store: store)
_ = controller   // retained for the app's lifetime

app.run()
