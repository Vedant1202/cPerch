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
    private let preferences: PreferencesStore
    private let popover = NSPopover()
    private let hosting: NSHostingController<RosterView>
    private let notifier = Notifier()
    private var previousSessions: [Session] = []
    private lazy var settingsWindow = SettingsWindowController(store: preferences)

    init(store: SessionProviding, preferences: PreferencesStore) {
        self.store = store
        self.preferences = preferences
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
        // A settings change re-applies the retention window to the store (Settings → General)
        // and re-renders the open roster (theme / view-mode).
        preferences.onChange = { [weak self] in
            guard let self else { return }
            DispatchQueue.main.async {
                self.store.setRetentionWindow(self.preferences.preferences.retention.seconds)
                self.updateRoster()
            }
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
        // Calm needs-input banners on →needsInput transitions (coalesced). DND mode +
        // notification life come from preferences; Focus suppression stays macOS's job.
        notifier.reconcile(previous: previousSessions, current: current,
                           preferences: preferences.preferences)
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
            maxListHeight: currentMaxListHeight(),
            viewMode: preferences.preferences.viewMode,
            onJump: { [weak self] session in self?.jump(to: session) },
            onSettings: { [weak self] in self?.openSettings() },
            onQuit: { NSApplication.shared.terminate(nil) }
        )
    }

    /// Open the Settings window (closing the transient popover first so it doesn't vanish
    /// the moment focus moves to the new window).
    private func openSettings() {
        popover.performClose(nil)
        settingsWindow.show()
    }

    /// The list's max height, responsive to the active screen so the popover never
    /// covers the whole display: ~60% of the screen's visible height, floored so it
    /// stays usable on small screens and bounded so it always leaves a margin.
    private func currentMaxListHeight() -> CGFloat {
        let screen = statusItem.button?.window?.screen ?? NSScreen.main
        let visibleH = screen?.visibleFrame.height ?? 900
        return min(max(visibleH * 0.6, 220), visibleH - 140)
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
        // Size the popover to the SwiftUI content (RosterView is a fixed 340pt wide); the
        // scrollable list is capped at a screen-relative height so a long roster scrolls
        // instead of growing past the display.
        let maxH = currentMaxListHeight()
        popover.contentSize = hosting.sizeThatFits(in: NSSize(width: 340, height: maxH + 120))
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
