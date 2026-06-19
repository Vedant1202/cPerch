import SwiftUI
import CPerchCore

/// The Settings window content — a two-tab form (General · Notifications), bound directly
/// to the shared `PreferencesStore`. Hosted in an NSWindow by `SettingsWindowController`.
struct SettingsView: View {
    @ObservedObject var store: PreferencesStore

    var body: some View {
        TabView {
            GeneralSettingsTab(prefs: $store.preferences)
                .tabItem { Label("General", systemImage: "gearshape") }
            NotificationSettingsTab(prefs: $store.preferences)
                .tabItem { Label("Notifications", systemImage: "bell") }
        }
        .frame(width: 480, height: 280)
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
