import SwiftUI
import CPerchCore

/// The Settings window content — a three-tab form (General · Notifications · Accessibility), bound
/// directly to the shared `PreferencesStore`. Hosted in an NSWindow by `SettingsWindowController`.
struct SettingsView: View {
    @ObservedObject var store: PreferencesStore

    var body: some View {
        TabView {
            GeneralSettingsTab(prefs: $store.preferences)
                .tabItem { Label("General", systemImage: "gearshape") }
            NotificationSettingsTab(prefs: $store.preferences)
                .tabItem { Label("Notifications", systemImage: "bell") }
            AccessibilitySettingsTab(prefs: $store.preferences)
                .tabItem { Label("Accessibility", systemImage: "accessibility") }
        }
        .frame(width: 480, height: 320)
        .padding(20)
    }
}

// MARK: - General

private struct GeneralSettingsTab: View {
    @Binding var prefs: Preferences

    var body: some View {
        Form {
            Picker("Theme", selection: $prefs.theme) {
                ForEach(AppTheme.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)

            Picker("Session list", selection: $prefs.viewMode) {
                ForEach(RosterViewMode.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.radioGroup)

            Picker("Keep finished sessions for", selection: $prefs.retention) {
                ForEach(RetentionWindow.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.menu)

            Toggle("Launch cPerch at login", isOn: $prefs.launchAtLogin)

            // If the user has cPerch switched OFF in System Settings ▸ General ▸ Login
            // Items, the OS reports `.requiresApproval`: the toggle can read "on" yet
            // nothing launches. Surface that so it isn't a silent mystery — only the user
            // can re-enable it there; an app can't override the choice (v0.4 #7).
            if prefs.launchAtLogin, LoginItem.status == .requiresApproval {
                Text("Enable in System Settings ▸ Login Items")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Notifications

private struct NotificationSettingsTab: View {
    @Binding var prefs: Preferences

    var body: some View {
        Form {
            // Per-kind notification toggles (v0.4 #4). needsInput + errors on by
            // default; completion is opt-in (calm ethos — finishing is the quiet case).
            Toggle("Needs input", isOn: $prefs.notifyOnNeedsInput)
            Toggle("Errors", isOn: $prefs.notifyOnError)
            Toggle("Completion", isOn: $prefs.notifyOnCompletion)
            Toggle("Show all-done glyph in menu bar", isOn: $prefs.showAllDoneGlyph)

            Picker("When Focus / DND is on", selection: $prefs.dndMode) {
                ForEach(DNDMode.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.radioGroup)

            Picker("Notification life", selection: $prefs.notificationDismiss) {
                ForEach(NotificationDismiss.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.radioGroup)

            if prefs.notificationDismiss == .timed {
                Stepper(value: $prefs.notificationTimeoutSeconds, in: Preferences.timeoutRange) {
                    Text("Dismiss after \(prefs.notificationTimeoutSeconds) s")
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Accessibility

private struct AccessibilitySettingsTab: View {
    @Binding var prefs: Preferences

    var body: some View {
        Form {
            // Shape-coded status is on by default (the "always-on" call, v0.5 A1); this is the
            // opt-out for the user who wants the pure colored dot.
            Toggle("Differentiate status with shapes", isOn: $prefs.showStatusShapes)

            // Three-way overrides (A3/A5/A6). Each defaults to "Follow System" — cPerch honors the
            // matching macOS Accessibility ▸ Display flag unless the user forces it on/off. Resolved
            // at render time by Core's `effective(_:system:)`.
            Picker("High contrast", selection: $prefs.highContrast) {
                ForEach(A11yOverride.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.menu)

            Picker("Reduce motion", selection: $prefs.reduceMotion) {
                ForEach(A11yOverride.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.menu)

            Picker("Reduce transparency", selection: $prefs.reduceTransparency) {
                ForEach(A11yOverride.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.menu)

            Text("\"Follow System\" uses your macOS Accessibility settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}
