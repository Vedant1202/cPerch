import Foundation
import ServiceManagement

// ─────────────────────────────────────────────────────────────────────────────
// #7 · LoginItem — "start cPerch when I log in" (Settings ▸ General toggle).
//
// A thin wrapper around `SMAppService.mainApp`, the macOS 13+ replacement for the
// deprecated SMLoginItemSetEnabled / LSSharedFileList APIs. Our deployment floor is
// macOS 14 (see Package.swift `.macOS(.v14)` + build.sh LSMinimumSystemVersion 14.0),
// so the API is always available — no `@available` fences or `#available` guards.
//
// `register()` enrolls *this* running app bundle as a login item; the OS persists the
// choice across launches, so we only (un)register when the user flips the toggle — we
// never re-assert it on every start (that's why PreferencesStore drives this from
// `preferences.didSet`, which doesn't fire during init).
//
// `status` reflects what the OS believes:
//   • .enabled         — will launch at login.
//   • .notRegistered   — not a login item.
//   • .requiresApproval — registered, but the user has it switched OFF in
//                         System Settings ▸ General ▸ Login Items. We surface this
//                         in the General tab so the toggle being "on" while nothing
//                         happens isn't a silent mystery — the user must re-enable it
//                         there; an app can't override that choice.
//
// Fully local — registering a login item is an OS-side bookkeeping call. No network,
// no Accessibility / Input Monitoring, nothing touching the auth token or ~/.claude.
//
// Side-effecty AppKit-adjacent glue with no unit-test target (it would mutate the real
// per-user login-item database): the bar is "compiles cleanly + structurally correct",
// matching Jumper.swift. (Un)register failures are swallowed — logged to stderr, never
// thrown — because a login-item hiccup must never crash the bar.
// ─────────────────────────────────────────────────────────────────────────────

enum LoginItem {

    /// Enroll (or remove) cPerch as a login item to match the user's preference.
    /// Errors are logged and swallowed — a failed (un)register must never crash the app.
    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            log("failed to \(enabled ? "register" : "unregister") login item: \(error)")
        }
    }

    /// What the OS currently believes about our login-item enrollment.
    static var status: SMAppService.Status { SMAppService.mainApp.status }

    /// Convenience: true only when we'll actually launch at login. `.requiresApproval`
    /// (user disabled us in System Settings) and `.notRegistered` both read as `false`.
    static var isEnabled: Bool { status == .enabled }

    /// Write a single diagnostic line to stderr. Mirrors Jumper's error-swallowing tone:
    /// we want a breadcrumb when (un)register fails, but never a crash or a user-facing alert.
    private static func log(_ message: String) {
        FileHandle.standardError.write(Data("cPerch LoginItem: \(message)\n".utf8))
    }
}
