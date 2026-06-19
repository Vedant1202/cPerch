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
        }
        .formStyle(.grouped)
    }
}

// MARK: - Notifications

private struct NotificationSettingsTab: View {
    @Binding var prefs: Preferences

    var body: some View {
        Form {
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
