import Foundation

// cPerch — user preferences (Settings window). A plain value type with UserDefaults
// persistence; the app wraps it in an ObservableObject and applies the side-effects
// (theme, view mode, notification behavior). Kept in CPerchCore — pure, Foundation-only,
// unit-tested — so the model + persistence are verifiable without the UI.

/// Appearance theme (General → Theme). `system` follows macOS.
public enum AppTheme: String, CaseIterable, Sendable, Codable {
    case system, light, dark
    public var label: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }
}

/// How the roster lays sessions out (General → View).
public enum RosterViewMode: String, CaseIterable, Sendable, Codable {
    case list             // flat, needs-you-first (default)
    case groupedBySource  // collapsible sections per source (CLI / Desktop / …)
    public var label: String {
        switch self {
        case .list:            return "Simple list"
        case .groupedBySource: return "Group by source"
        }
    }
}

/// How notifications interact with macOS Focus / Do Not Disturb (Notifications → DND).
public enum DNDMode: String, CaseIterable, Sendable, Codable {
    case system        // respect Focus/DND — let macOS decide (default)
    case notifyAnyway  // best-effort bypass (time-sensitive interruption level)
    case silentAlways  // always deliver, without sound
    public var label: String {
        switch self {
        case .system:       return "Respect system Focus / DND"
        case .notifyAnyway: return "Notify anyway"
        case .silentAlways: return "Silent always"
        }
    }
}

/// How long a delivered notification lingers (Notifications → Notification life).
public enum NotificationDismiss: String, CaseIterable, Sendable, Codable {
    case timed      // auto-clear after `notificationTimeoutSeconds` (default)
    case persisted  // stays in Notification Center until the user dismisses it
    public var label: String {
        switch self {
        case .timed:     return "Auto-dismiss after a delay"
        case .persisted: return "Keep until dismissed"
        }
    }
}

/// All cPerch preferences. Persistence is via `UserDefaults` (see `load`/`save`).
public struct Preferences: Equatable, Sendable {
    public var theme: AppTheme
    public var viewMode: RosterViewMode
    public var dndMode: DNDMode
    public var notificationDismiss: NotificationDismiss
    public var notificationTimeoutSeconds: Int

    /// Sensible starter defaults: follow the system, a simple list, respect Focus/DND, and
    /// auto-dismiss notifications after a calm **10 s** (long enough to notice, short enough
    /// to stay out of the way).
    public static let defaults = Preferences(
        theme: .system, viewMode: .list, dndMode: .system,
        notificationDismiss: .timed, notificationTimeoutSeconds: 10)

    /// Allowed range for the auto-dismiss delay (seconds), clamped on load/set.
    public static let timeoutRange: ClosedRange<Int> = 2...120

    public init(theme: AppTheme, viewMode: RosterViewMode, dndMode: DNDMode,
                notificationDismiss: NotificationDismiss, notificationTimeoutSeconds: Int) {
        self.theme = theme
        self.viewMode = viewMode
        self.dndMode = dndMode
        self.notificationDismiss = notificationDismiss
        self.notificationTimeoutSeconds =
            notificationTimeoutSeconds.clamped(to: Preferences.timeoutRange)
    }

    // MARK: - UserDefaults persistence (keys namespaced under "pref.")

    private enum Key {
        static let theme = "pref.theme"
        static let viewMode = "pref.viewMode"
        static let dndMode = "pref.dndMode"
        static let dismiss = "pref.notificationDismiss"
        static let timeout = "pref.notificationTimeoutSeconds"
    }

    /// Load from `store`, falling back to `.defaults` for any missing or unrecognized
    /// value (so a partial/older domain still yields a complete, valid Preferences).
    public static func load(from store: UserDefaults) -> Preferences {
        var p = Preferences.defaults
        if let raw = store.string(forKey: Key.theme), let v = AppTheme(rawValue: raw) { p.theme = v }
        if let raw = store.string(forKey: Key.viewMode), let v = RosterViewMode(rawValue: raw) { p.viewMode = v }
        if let raw = store.string(forKey: Key.dndMode), let v = DNDMode(rawValue: raw) { p.dndMode = v }
        if let raw = store.string(forKey: Key.dismiss), let v = NotificationDismiss(rawValue: raw) { p.notificationDismiss = v }
        if store.object(forKey: Key.timeout) != nil {
            p.notificationTimeoutSeconds = store.integer(forKey: Key.timeout).clamped(to: timeoutRange)
        }
        return p
    }

    /// Persist every field to `store`.
    public func save(to store: UserDefaults) {
        store.set(theme.rawValue, forKey: Key.theme)
        store.set(viewMode.rawValue, forKey: Key.viewMode)
        store.set(dndMode.rawValue, forKey: Key.dndMode)
        store.set(notificationDismiss.rawValue, forKey: Key.dismiss)
        store.set(notificationTimeoutSeconds, forKey: Key.timeout)
    }
}

extension Comparable {
    /// Clamp to a closed range.
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
