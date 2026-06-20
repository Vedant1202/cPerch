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
    /// v0.6 — true while the one-time first-run Help hint is on screen (controller-owned TTL).
    private var helpHintActive = false
    private lazy var settingsWindow = SettingsWindowController(store: preferences)

    init(store: SessionProviding, preferences: PreferencesStore) {
        self.store = store
        self.preferences = preferences
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        hosting = NSHostingController(rootView: RosterView(sessions: store.sessions))
        super.init()

        popover.behavior = .transient
        // A5 — honor Reduce Motion (system flag or the tab's override): no popover
        // animation when effective. Re-applied in `refresh()` so it tracks live changes.
        popover.animates = !effective(preferences.preferences.reduceMotion,
                                      system: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        popover.contentViewController = hosting
        // Let SwiftUI drive the popover size so it resizes when the content swaps between the session
        // list and the (taller) in-app Help view (v0.6). Each caps its own height to the screen.
        hosting.sizingOptions = [.preferredContentSize]

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover)
            button.toolTip = "cPerch"
            // A4 — a stable VoiceOver label for the bar item; the live state rides on the
            // value (set per-refresh below).
            button.setAccessibilityLabel("cPerch")
        }

        store.onChange = { [weak self] in
            DispatchQueue.main.async { self?.refresh() }
        }
        // A settings change re-applies the retention window to the store (Settings → General),
        // re-renders the open roster (theme / view-mode), and refreshes the bar dot so an
        // a11y pref flip (high contrast / shapes / reduce-motion) takes effect live.
        preferences.onChange = { [weak self] in
            guard let self else { return }
            DispatchQueue.main.async {
                self.store.setRetentionWindow(self.preferences.preferences.retention.seconds)
                self.refresh()
                self.updateRoster()
            }
        }
        // A3/A5 — react live to the system Accessibility ▸ Display flags (Increase Contrast,
        // Reduce Motion) without a relaunch. These are the *readable* display preferences,
        // not the Accessibility (AX) control permission. Removed in `deinit`.
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(accessibilityDisplayOptionsDidChange),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil)

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

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(
            self,
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil)
    }

    /// The system Accessibility ▸ Display options changed (Increase Contrast / Reduce Motion /
    /// …). Re-render on the main queue so the bar dot, count color, and popover animation track
    /// the live flags. (A3/A5.)
    @objc private func accessibilityDisplayOptionsDidChange() {
        DispatchQueue.main.async { [weak self] in self?.refresh() }
    }

    // MARK: - Bar dot

    /// Map an abstract `MenuBarModel.Glyph` (from CPerchCore — color-free) to its design-token
    /// dot color, honoring high contrast + the bar's appearance (A2/A3). The decision of *which*
    /// glyph lives in the Core; the color binding lives here in the App layer. `idle` stays the
    /// dim gray (no high-contrast swap — it's the quiet resting state, not a brand accent); the
    /// three live states route through `Tokens.statusColor`, which picks the brand or HC fill.
    private func color(for glyph: MenuBarModel.Glyph) -> NSColor {
        let highContrast = effective(
            preferences.preferences.highContrast,
            system: NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast)
        let dark = isDarkBar
        switch glyph {
        case .needsInput: return Tokens.statusColor(.needsInput, highContrast: highContrast, dark: dark)
        case .running:    return Tokens.statusColor(.running, highContrast: highContrast, dark: dark)
        case .allDone:    return Tokens.statusColor(.concluded, highContrast: highContrast, dark: dark)
        case .idle:       return Tokens.idleDim
        }
    }

    /// Whether the menu bar is currently rendering dark, so the high-contrast palette can pick
    /// its light/dark variant (A3). The status item's button follows the bar's effective
    /// appearance (which itself tracks the menu-bar tint / system theme).
    private var isDarkBar: Bool {
        let appearance = statusItem.button?.effectiveAppearance ?? NSApp.effectiveAppearance
        return appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
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
        // A5 — keep the popover animation in sync with the live Reduce-Motion state (the
        // system flag or the tab's override can change while the app runs).
        popover.animates = !effective(preferences.preferences.reduceMotion,
                                      system: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        if let button = statusItem.button {
            let dotColor = color(for: model.glyph)
            // A1 — shape-coded dot: a distinct SF Symbol per status (tinted, full color) when the
            // user keeps shapes on (default); the plain colored oval when they opt out. Either way
            // the glyph rides on a white plate (`plated`) so it never blends into a light or busy
            // wallpaper behind the translucent menu bar — a fixed-hue dot has no guaranteed contrast
            // there, and the bar can't be assumed light or dark.
            let foreground = preferences.preferences.showStatusShapes
                ? (Self.symbolForeground(for: model.glyph, color: dotColor) ?? Self.dotImage(color: dotColor))
                : Self.dotImage(color: dotColor)
            let image = Self.plated(foreground)
            button.image = image
            button.imagePosition = model.count == nil ? .imageOnly : .imageLeft
            // The needs-you count rides next to the dot — small and subtle, no quota text.
            if let count = model.count {
                button.attributedTitle = Self.countTitle(count)
            } else {
                button.attributedTitle = NSAttributedString(string: "")
            }
            // A4 — the live VoiceOver value: the most-urgent summary ("2 sessions need you" /
            // "1 running" / "all quiet"). The static label ("cPerch") is set once in `init`.
            button.setAccessibilityValue(
                menuBarAccessibilityValue(aggregate: store.aggregate,
                                          needsInputCount: needsInputCount,
                                          runningCount: current.filter { $0.status == .running }.count))
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
            onQuit: { NSApplication.shared.terminate(nil) },
            preferences: preferences.preferences,
            showHelpHint: helpHintActive
        )
    }

    /// First-run Help hint (v0.6): the first time the popover ever opens, flag the "?" callout, persist
    /// `hasSeenHelpHint` so it never returns, and auto-dismiss after a few seconds.
    private func maybeShowHelpHint() {
        guard !preferences.preferences.hasSeenHelpHint else { return }
        helpHintActive = true
        preferences.preferences.hasSeenHelpHint = true   // persists via PreferencesStore's didSet
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) { [weak self] in
            guard let self else { return }
            self.helpHintActive = false
            self.updateRoster()
        }
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
        maybeShowHelpHint()
        updateRoster()
        // The popover sizes itself to the SwiftUI content (`hosting.sizingOptions`), so it fits both
        // the session list and the taller Help view; each caps its height to the screen.
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

    /// The per-status bar glyph. On the white plate the plate IS the enclosure, so we use the BARE
    /// marks here — not the roster's enclosed `.circle.fill` set — so it reads as a clear colored mark
    /// (green check / orange ! / blue in-progress) on white, rather than a colored disc with a faint
    /// white knockout. (The roster keeps the enclosed set via `Tokens.symbolName`.)
    private static func barGlyphName(for glyph: MenuBarModel.Glyph) -> String {
        switch glyph {
        case .needsInput: return "exclamationmark"
        case .running:    return "circle.lefthalf.filled"
        case .allDone:    return "checkmark"
        case .idle:       return "circle.fill"
        }
    }

    /// The bar glyph as a *foreground* image, explicitly tinted. We draw the symbol as a TEMPLATE and
    /// fill it with the status color (`sourceAtop`) rather than using a palette `SymbolConfiguration`,
    /// because a palette color is LOST when the image is later composited onto the plate via `draw()`
    /// — it only survives when a control renders the symbol directly. Returns nil if the symbol is
    /// missing so the caller can fall back to the plain oval. `plated(_:)` composites this onto white.
    private static func symbolForeground(for glyph: MenuBarModel.Glyph, color: NSColor,
                                         pointSize: CGFloat = 10) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .bold)
        guard let base = NSImage(systemSymbolName: barGlyphName(for: glyph), accessibilityDescription: nil)?
                .withSymbolConfiguration(config) else { return nil }
        let size = base.size
        let tinted = NSImage(size: size)
        tinted.lockFocus()
        base.isTemplate = true
        base.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
        color.set()
        NSRect(origin: .zero, size: size).fill(using: .sourceAtop)   // recolor the glyph, keep its alpha
        tinted.unlockFocus()
        tinted.isTemplate = false
        return tinted
    }

    /// Composite a foreground glyph onto a white circular plate with a faint hairline edge, so the
    /// colored dot reads on ANY desktop behind the translucent menu bar — light, dark, or busy. A
    /// fixed-hue dot alone can vanish into a similar-toned wallpaper; the white backing + edge give
    /// it a guaranteed contrasting surface. (Menu-bar only — roster dots sit on a controlled bg.)
    private static func plated(_ foreground: NSImage, diameter: CGFloat = 16) -> NSImage {
        let image = NSImage(size: NSSize(width: diameter, height: diameter))
        image.lockFocus()
        let inset: CGFloat = 0.75
        let plate = NSBezierPath(ovalIn: NSRect(x: inset, y: inset,
                                                width: diameter - 2 * inset,
                                                height: diameter - 2 * inset))
        NSColor.white.setFill()
        plate.fill()
        NSColor(white: 0, alpha: 0.18).setStroke()   // faint edge so white-on-white still has a rim
        plate.lineWidth = 1
        plate.stroke()
        let fg = foreground.size
        foreground.draw(at: NSPoint(x: (diameter - fg.width) / 2, y: (diameter - fg.height) / 2),
                        from: .zero, operation: .sourceOver, fraction: 1)
        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    /// The needs-you count shown next to the dot — small and subtle. Uses the semantic
    /// `labelColor` so it stays legible against any menu-bar background (light, dark, or a
    /// tinted/“Reduce transparency” bar) instead of a fixed accent that can wash out (A2). A
    /// leading hair-space gives the dot a little breathing room.
    private static func countTitle(_ count: Int) -> NSAttributedString {
        NSAttributedString(string: "\u{200A}\(count)", attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
        ])
    }
}
