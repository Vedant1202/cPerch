import AppKit
import CPerchCore

// ─────────────────────────────────────────────────────────────────────────────
// P1-E · Jumper — "take me to the session, never spawn a duplicate."
//
// Switches on `Session.host` (the frozen `HostRef` contract in CPerchCore):
//   • .terminal(app, tty) → focus the EXISTING tab whose tty matches, via Apple
//     Events (NSAppleScript). Supports Terminal.app and iTerm2; selected by `app`,
//     defaulting to Terminal. Never opens a new window/tab.
//   • .desktop(bundleID)  → activate the already-running app via NSWorkspace. If it
//     isn't running, do nothing (do NOT launch a duplicate).
//   • .unknown            → no-op.
//
// PERMISSIONS: the terminal path uses Apple Events to script another app, which
// requires the macOS Automation (TCC) permission. The app's Info.plist must carry
// an `NSAppleEventsUsageDescription` string — wired up in Phase 3 (build.sh). The
// FIRST jump to a given terminal triggers the system "… wants to control …"
// Automation prompt; once granted, subsequent jumps are silent. The NSWorkspace
// desktop path needs no special permission.
//
// This is side-effecty AppKit/AppleScript glue with no unit-test target: it can't
// be exercised without live Terminal/iTerm windows and a real desktop app, so the
// bar here is "compiles cleanly + structurally-correct AppleScript". Verified by
// hand in Phase 4 against live sessions.
// ─────────────────────────────────────────────────────────────────────────────

public enum Jumper {

    /// Focus the existing host window/tab for `session`. Never spawns a duplicate.
    public static func jump(to session: Session) {
        switch session.host {
        case let .terminal(app, tty):
            focusTerminalTab(app: app, tty: tty)
        case let .desktop(bundleID):
            activateRunningApp(bundleID: bundleID)
        case .unknown:
            break   // nothing actionable
        }
    }

    // MARK: - Terminal (Apple Events)

    /// Which terminal an Apple Events jump targets. Resolved from the `app` string
    /// on `HostRef.terminal`; anything we don't recognise falls back to Terminal.
    private enum TerminalApp {
        case appleTerminal
        case iTerm2

        /// Match loosely on the host's `app` field — it may be a bundle id
        /// ("com.googlecode.iterm2"), a process name ("iTerm2"), or an app name
        /// ("Terminal"). Default to Apple Terminal when unsure.
        init(matching app: String) {
            let a = app.lowercased()
            if a.contains("iterm") {
                self = .iTerm2
            } else {
                self = .appleTerminal
            }
        }
    }

    /// Build + run the AppleScript that selects the tab whose tty matches and
    /// raises its window. Runs on the main thread (NSAppleScript requirement).
    private static func focusTerminalTab(app: String, tty: String) {
        let source: String
        switch TerminalApp(matching: app) {
        case .appleTerminal:
            source = appleTerminalScript(tty: tty)
        case .iTerm2:
            source = iTerm2Script(tty: tty)
        }
        runAppleScript(source)
    }

    /// Terminal.app: every `tab` exposes a `tty` (e.g. "/dev/ttys003"). We find the
    /// matching tab, mark it selected (Terminal brings its window forward when a tab
    /// is selected and the app is activated), then activate. No `do script`, no new
    /// window — selection only.
    private static func appleTerminalScript(tty: String) -> String {
        let q = escapeForAppleScript(tty)
        return """
        tell application "Terminal"
            repeat with w in windows
                repeat with t in tabs of w
                    if tty of t is "\(q)" then
                        set selected of t to true
                        set frontmost of w to true
                        activate
                        return
                    end if
                end repeat
            end repeat
        end tell
        """
    }

    /// iTerm2: the tty lives on a `session` (window → tab → session). `select` on the
    /// session makes its tab current and raises the window; we then activate the app.
    /// No `create window`/`create tab` — we only select an existing session.
    private static func iTerm2Script(tty: String) -> String {
        let q = escapeForAppleScript(tty)
        return """
        tell application "iTerm2"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if tty of s is "\(q)" then
                            select s
                            select t
                            activate
                            return
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        """
    }

    /// Escape a value for safe interpolation inside an AppleScript double-quoted
    /// string literal. ttys are device paths ("/dev/ttysNNN") with no special
    /// characters in practice, but we defend against backslashes/quotes regardless
    /// so a surprising value can never break out of the string or inject script.
    private static func escapeForAppleScript(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// Compile + execute an AppleScript. Apple Events must be issued from the main
    /// thread, so hop there if we're called off it. Errors (e.g. Automation denied,
    /// app not running) are swallowed — a failed jump must never crash the bar; the
    /// caller can fall back to activate-the-app at a higher layer.
    private static func runAppleScript(_ source: String) {
        let execute = {
            guard let script = NSAppleScript(source: source) else { return }
            var error: NSDictionary?
            script.executeAndReturnError(&error)
            // `error` is intentionally ignored beyond not crashing; live-tested in P4.
        }
        if Thread.isMainThread {
            execute()
        } else {
            DispatchQueue.main.async(execute: execute)
        }
    }

    // MARK: - Desktop (NSWorkspace)

    /// Activate the already-running app with this bundle id (e.g.
    /// "com.anthropic.claudefordesktop"). If no instance is running we do nothing —
    /// launching would create a duplicate, which the spec forbids.
    private static func activateRunningApp(bundleID: String) {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        guard let appInstance = running.first else { return }   // not running → no-op
        appInstance.activate(options: [.activateAllWindows])
    }
}
