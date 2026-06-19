import Foundation

// cPerch — user preferences (Settings window). A plain value type with UserDefaults
// persistence; the app wraps it in an ObservableObject and applies the side-effects
// (theme, view mode, notification behavior, retention). Kept in CPerchCore — pure,
// Foundation-only, unit-tested — so the model + persistence are verifiable without the UI.

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
    case groupedBySource  // collapsible sections per source (Terminal / Claude App / …)
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

/// How long a *concluded* session lingers on the roster before eviction (General → Keep
/// finished sessions for). The roster only ever holds live sessions + concluded ones inside
/// this window (and the 10 most-recent); a shorter window drops resume-ancestors / ghosts
/// faster, a longer one keeps more history. Raw value is **minutes**.
public enum RetentionWindow: Int, CaseIterable, Sendable, Codable {
    case m30 = 30, h1 = 60, h3 = 180, h6 = 360, h12 = 720, h24 = 1440
    /// The window in seconds — the unit `SessionStore` retains by.
    public var seconds: TimeInterval { TimeInterval(rawValue * 60) }
    public var label: String {
        switch self {
        case .m30: return "30 minutes"
        case .h1:  return "1 hour"
        case .h3:  return "3 hours"
        case .h6:  return "6 hours"
        case .h12: return "12 hours"
        case .h24: return "24 hours"
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
    public var retention: RetentionWindow

    /// Sensible starter defaults: follow the system, a simple list, respect Focus/DND,
    /// auto-dismiss notifications after a calm **10 s**, and keep finished sessions **3 h**
    /// (the prior hard-coded `SessionStore` retention).
    public static let defaults = Preferences(
        theme: .system, viewMode: .list, dndMode: .system,
        notificationDismiss: .timed, notificationTimeoutSeconds: 10, retention: .h3)

    /// Allowed range for the auto-dismiss delay (seconds), clamped on load/set.
    public static let timeoutRange: ClosedRange<Int> = 2...120

    public init(theme: AppTheme, viewMode: RosterViewMode, dndMode: DNDMode,
                notificationDismiss: NotificationDismiss, notificationTimeoutSeconds: Int,
                retention: RetentionWindow = .h3) {
        self.theme = theme
        self.viewMode = viewMode
        self.dndMode = dndMode
        self.notificationDismiss = notificationDismiss
        self.notificationTimeoutSeconds =
            notificationTimeoutSeconds.clamped(to: Preferences.timeoutRange)
        self.retention = retention
    }

    // MARK: - UserDefaults persistence (keys namespaced under "pref.")

    private enum Key {
        static let theme = "pref.theme"
        static let viewMode = "pref.viewMode"
        static let dndMode = "pref.dndMode"
        static let dismiss = "pref.notificationDismiss"
        static let timeout = "pref.notificationTimeoutSeconds"
        static let retention = "pref.retentionMinutes"
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
        if store.object(forKey: Key.retention) != nil,
           let v = RetentionWindow(rawValue: store.integer(forKey: Key.retention)) {
            p.retention = v
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
        store.set(retention.rawValue, forKey: Key.retention)
    }
}

extension Comparable {
    /// Clamp to a closed range.
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
