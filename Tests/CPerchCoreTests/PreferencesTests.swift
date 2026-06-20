import Testing
import Foundation
@testable import CPerchCore

// Preferences is a pure value type with UserDefaults persistence (the Settings window
// model). These pin the defaults, the load/save round-trip, clamping, and graceful
// fallback for missing/unknown values — all without the UI.

@Suite("Preferences — defaults, persistence, clamping")
struct PreferencesTests {

    /// An isolated, throwaway UserDefaults domain so tests never touch the real one.
    private func scratch() -> UserDefaults {
        UserDefaults(suiteName: "cperch.tests.\(UUID().uuidString)")!
    }

    @Test("defaults: system theme / simple list / respect DND / timed 10s")
    func defaults() {
        let p = Preferences.defaults
        #expect(p.theme == .system)
        #expect(p.viewMode == .list)
        #expect(p.dndMode == .system)
        #expect(p.notificationDismiss == .timed)
        #expect(p.notificationTimeoutSeconds == 10)
        #expect(p.retention == .h3)              // 3h — the prior hard-coded default
        #expect(p.retention.seconds == 3 * 3600)
        // v0.4 batch defaults: notify on needs-input + error, completion opt-in, all-done glyph on,
        // launch-at-login off.
        #expect(p.notifyOnNeedsInput == true)
        #expect(p.notifyOnError == true)
        #expect(p.notifyOnCompletion == false)
        #expect(p.showAllDoneGlyph == true)
        #expect(p.launchAtLogin == false)
        // v0.5 accessibility defaults: status shapes on, every override follows the system.
        #expect(p.showStatusShapes == true)
        #expect(p.highContrast == .system)
        #expect(p.reduceMotion == .system)
        #expect(p.reduceTransparency == .system)
        // v0.6 in-app Help: the first-run hint hasn't been seen yet.
        #expect(p.hasSeenHelpHint == false)
    }

    @Test("an empty store loads exactly the defaults")
    func loadEmptyIsDefaults() {
        #expect(Preferences.load(from: scratch()) == .defaults)
    }

    @Test("save then load round-trips every field")
    func roundTrip() {
        let store = scratch()
        let p = Preferences(theme: .dark, viewMode: .groupedBySource, dndMode: .notifyAnyway,
                            notificationDismiss: .persisted, notificationTimeoutSeconds: 25,
                            retention: .h12,
                            notifyOnNeedsInput: false, notifyOnError: false,
                            notifyOnCompletion: true, showAllDoneGlyph: false,
                            launchAtLogin: true,
                            showStatusShapes: false, highContrast: .on,
                            reduceMotion: .off, reduceTransparency: .on,
                            hasSeenHelpHint: true)
        p.save(to: store)
        #expect(Preferences.load(from: store) == p)
    }

    @Test("effective(): .on/.off ignore the system flag, .system mirrors it")
    func effectiveOverride() {
        #expect(effective(.on, system: false) == true)
        #expect(effective(.on, system: true) == true)
        #expect(effective(.off, system: true) == false)
        #expect(effective(.off, system: false) == false)
        #expect(effective(.system, system: true) == true)
        #expect(effective(.system, system: false) == false)
    }

    @Test("an unrecognized stored value falls back to that field's default")
    func unknownValueFallsBack() {
        let store = scratch()
        store.set("chartreuse", forKey: "pref.theme")
        store.set("mosaic", forKey: "pref.viewMode")
        let p = Preferences.load(from: store)
        #expect(p.theme == .system)     // bad value ignored
        #expect(p.viewMode == .list)
    }

    @Test("timeout is clamped to the allowed range on init and load")
    func timeoutClamped() {
        #expect(Preferences(theme: .system, viewMode: .list, dndMode: .system,
                            notificationDismiss: .timed, notificationTimeoutSeconds: 9999)
                    .notificationTimeoutSeconds == Preferences.timeoutRange.upperBound)
        let store = scratch()
        store.set(0, forKey: "pref.notificationTimeoutSeconds")
        #expect(Preferences.load(from: store).notificationTimeoutSeconds == Preferences.timeoutRange.lowerBound)
    }
}
