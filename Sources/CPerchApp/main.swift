import AppKit
import CPerchCore

// cPerch — menu-bar agent (LSUIElement / no Dock icon).

// `--print` debug mode (P2): run the real SessionStore once, print the sessions, and exit —
// without starting the menu bar (the stub → real-store UI swap is Phase 3).
if CommandLine.arguments.contains("--print") {
    let store = SessionStore()
    store.refresh()
    func glyph(_ s: DerivedStatus) -> String {
        switch s {
        case .needsInput: return "🟠"
        case .running:    return "🔵"
        case .concluded:  return "✅"
        }
    }
    let rows = store.sessions
    print("\ncPerch · --print · \(rows.count) sessions\n")
    for s in rows {
        let host: String
        switch s.host {
        case let .terminal(app, tty): host = "\(app):\(tty)"
        case .desktop:                host = "desktop"
        case .unknown:                host = "—"
        }
        let status = s.status.rawValue.padding(toLength: 11, withPad: " ", startingAt: 0)
        print("  \(glyph(s.status)) \(status) \(s.displayName)  pid=\(s.pid.map(String.init) ?? "—")  host=\(host)")
        if let m = s.latestMessage, !m.isEmpty {
            print("       ↳ \(m.replacingOccurrences(of: "\n", with: " ").prefix(72))")
        }
    }
    print("")
    exit(0)
}

// Live menu bar: the real SessionStore drives the aggregate dot + roster.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let prefs = PreferencesStore()
prefs.applyTheme()   // apply the saved appearance at launch

let store = SessionStore()
let controller = MenuBarController(store: store, preferences: prefs)
_ = controller   // retained for the app's lifetime

app.run()
