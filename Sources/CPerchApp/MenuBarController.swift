import AppKit
import CPerchCore

/// P0 skeleton: an `NSStatusItem` whose dot reflects the store's aggregate state,
/// plus a minimal text menu listing sessions. The rich SwiftUI roster is P1-D.
final class MenuBarController {
    private let statusItem: NSStatusItem
    private let store: SessionProviding

    init(store: SessionProviding) {
        self.store = store
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        store.onChange = { [weak self] in
            DispatchQueue.main.async { self?.refresh() }
        }
        store.start()
        refresh()
    }

    private func color(for state: AggregateState) -> NSColor {
        switch state {
        case .needsInput: return Tokens.needsInput
        case .running:    return Tokens.running
        case .idle:       return Tokens.idleDim
        }
    }

    private func refresh() {
        if let button = statusItem.button {
            let image = Self.dotImage(color: color(for: store.aggregate))
            image.isTemplate = false
            button.image = image
            button.toolTip = "cPerch"
        }
        statusItem.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        if store.sessions.isEmpty {
            menu.addItem(NSMenuItem(title: "No active sessions", action: nil, keyEquivalent: ""))
        } else {
            for s in store.sessions {
                let dot: String
                switch s.status {
                case .needsInput: dot = "🟠"
                case .running:    dot = "🔵"
                case .concluded:  dot = "✅"
                }
                menu.addItem(NSMenuItem(title: "\(dot)  \(s.displayName) — \(s.status.rawValue)",
                                        action: nil, keyEquivalent: ""))
            }
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit cPerch",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
        return menu
    }

    private static func dotImage(color: NSColor, diameter: CGFloat = 10) -> NSImage {
        let size = NSSize(width: diameter, height: diameter)
        let image = NSImage(size: size)
        image.lockFocus()
        color.setFill()
        NSBezierPath(ovalIn: NSRect(x: 0, y: 0, width: diameter, height: diameter)).fill()
        image.unlockFocus()
        return image
    }
}
