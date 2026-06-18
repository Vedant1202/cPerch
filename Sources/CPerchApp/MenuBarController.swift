import AppKit
import SwiftUI
import CPerchCore

/// Owns the `NSStatusItem`: paints the aggregate dot in the bar and hosts the rich
/// SwiftUI `RosterView` (P1-D) in an `NSPopover` shown when the bar button is clicked.
///
/// The dot reflects `store.aggregate` (most-urgent-wins, live-only); the popover lists
/// the sessions. Both refresh on the store's `onChange`. Jump is a placeholder until the
/// real Jumper integrates in P3.
final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let store: SessionProviding
    private let popover = NSPopover()
    private let hosting: NSHostingController<RosterView>
    private let notifier = Notifier()
    private var previousSessions: [Session] = []

    init(store: SessionProviding) {
        self.store = store
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        hosting = NSHostingController(rootView: RosterView(sessions: store.sessions))
        super.init()

        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = hosting

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover)
            button.toolTip = "cPerch"
        }

        store.onChange = { [weak self] in
            DispatchQueue.main.async { self?.refresh() }
        }
        store.start()
        refresh()
    }

    // MARK: - Bar dot

    private func color(for state: AggregateState) -> NSColor {
        switch state {
        case .needsInput: return Tokens.needsInput
        case .running:    return Tokens.running
        case .idle:       return Tokens.idleDim
        }
    }

    private func refresh() {
        let current = store.sessions
        if let button = statusItem.button {
            let image = Self.dotImage(color: color(for: store.aggregate))
            image.isTemplate = false
            button.image = image
        }
        // Calm needs-input banners on →needsInput transitions (coalesced; DND-aware via macOS).
        notifier.reconcile(previous: previousSessions, current: current)
        previousSessions = current
        // Keep the open roster in sync with live session changes.
        updateRoster()
    }

    private func updateRoster() {
        hosting.rootView = makeRoster()
    }

    private func makeRoster() -> RosterView {
        RosterView(
            sessions: store.sessions,
            onJump: { [weak self] session in self?.jump(to: session) },
            onQuit: { NSApplication.shared.terminate(nil) }
        )
    }

    // MARK: - Popover

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        updateRoster()
        // Size the popover to the SwiftUI content (RosterView is a fixed 340pt wide).
        popover.contentSize = hosting.sizeThatFits(in: NSSize(width: 340, height: 600))
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    // MARK: - Jump (placeholder — real Jumper lands in P3)

    private func jump(to session: Session) {
        Jumper.jump(to: session)   // focus the existing host window/tab; never a duplicate
        popover.performClose(nil)
    }

    // MARK: - Bar dot rendering

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
