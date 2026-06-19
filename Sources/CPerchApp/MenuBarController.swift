import AppKit
import SwiftUI
import Carbon.HIToolbox
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
    private var hotkey: GlobalHotkey?
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

        // System-wide ⌘⌥` toggles the popover. Registered by physical key CODE
        // (`kVK_ANSI_Grave`) so it tracks the top-left key across layouts. Via Carbon
        // (no TCC permission); a nil result (chord already claimed) just means no
        // hotkey — the bar still works by click.
        hotkey = GlobalHotkey(keyCode: UInt32(kVK_ANSI_Grave),
                              modifiers: UInt32(cmdKey | optionKey)) { [weak self] in
            self?.togglePopover()
        }
    }

    // MARK: - Bar dot

    /// Map an abstract `MenuBarModel.Glyph` (from CPerchCore — color-free) to its
    /// design-token dot color. The decision of *which* glyph lives in the Core; the
    /// color binding lives here in the App layer.
    private func color(for glyph: MenuBarModel.Glyph) -> NSColor {
        switch glyph {
        case .needsInput: return Tokens.needsInput
        case .running:    return Tokens.running
        case .idle:       return Tokens.idleDim
        case .allDone:    return Tokens.concluded
        }
    }

    private func refresh() {
        let current = store.sessions
        // Pre-compute the pure model's inputs, then let CPerchCore decide the glyph +
        // optional needs-you count (≥2). all-done glyph is gated by the preference.
        let needsInputCount = current.filter { $0.status == .needsInput }.count
        let allConcluded = !current.isEmpty && current.allSatisfy { $0.status == .concluded }
        let model = menuBarModel(aggregate: store.aggregate,
                                 needsInputCount: needsInputCount,
                                 allConcluded: allConcluded,
                                 allDoneGlyphEnabled: preferences.preferences.showAllDoneGlyph)
        if let button = statusItem.button {
            let image = Self.dotImage(color: color(for: model.glyph))
            image.isTemplate = false
            button.image = image
            button.imagePosition = model.count == nil ? .imageOnly : .imageLeft
            // The needs-you count rides next to the dot — small and subtle, no quota text.
            if let count = model.count {
                button.attributedTitle = Self.countTitle(count)
            } else {
                button.attributedTitle = NSAttributedString(string: "")
            }
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
        // cPerch is an accessory/background app, so the popover won't come forward or
        // take focus on its own when opened via the global hotkey (no click to make us
        // active). Activate first so it appears above other apps and is key. Harmless
        // on the click path, where we're already active.
        NSApp.activate(ignoringOtherApps: true)
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

    /// The needs-you count shown next to the dot — small, subtle, in the orange accent
    /// so it reads as part of the needs-input state. A leading hair-space gives the dot
    /// a little breathing room.
    private static func countTitle(_ count: Int) -> NSAttributedString {
        NSAttributedString(string: "\u{200A}\(count)", attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: Tokens.needsInput,
        ])
    }
}
