import AppKit
import SwiftUI

/// Owns the single, reused Settings window. cPerch is an `LSUIElement` accessory with no
/// Dock icon, so opening Settings must **activate** the app and bring the window to the
/// front (otherwise the window would appear behind everything, unfocusable).
final class SettingsWindowController {
    private let store: PreferencesStore
    private var window: NSWindow?

    init(store: PreferencesStore) { self.store = store }

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView(store: store))
            let w = NSWindow(contentViewController: hosting)
            w.title = "cPerch Settings"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false   // reuse across opens
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
