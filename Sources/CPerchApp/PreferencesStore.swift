import AppKit
import SwiftUI
import CPerchCore

/// Observable wrapper around `Preferences`, persisted to `UserDefaults.standard`. The
/// Settings UI binds to it; mutating any field saves, re-applies the appearance, and
/// notifies the app (so the open roster picks up a view-mode/theme change live).
final class PreferencesStore: ObservableObject {
    @Published var preferences: Preferences {
        didSet {
            guard preferences != oldValue else { return }
            preferences.save(to: defaults)
            applyTheme()
            onChange?()
        }
    }

    /// Invoked after any change — MenuBarController uses it to refresh the roster.
    var onChange: (() -> Void)?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.preferences = Preferences.load(from: defaults)
    }

    /// Apply the appearance theme app-wide (menu-bar popover + Settings window). A nil
    /// appearance means "follow the system" (the default).
    func applyTheme() {
        NSApp.appearance = preferences.theme.nsAppearance
    }
}

extension AppTheme {
    /// The matching `NSAppearance` (nil ⇒ follow the system).
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light:  return NSAppearance(named: .aqua)
        case .dark:   return NSAppearance(named: .darkAqua)
        }
    }
}
