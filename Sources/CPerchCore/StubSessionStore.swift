import Foundation

/// Phase-0 walking-skeleton store: hardcoded sessions across states so the menu-bar
/// skeleton renders before real detection (Phase 2) exists. Replaced by `SessionStore`.
public final class StubSessionStore: SessionProviding {
    public private(set) var sessions: [Session]
    public var onChange: (() -> Void)?

    public init() {
        let now = Date()
        sessions = [
            Session(id: "stub-needsinput",
                    projectPath: "/Users/you/Projects/api", displayName: "api",
                    source: .cli, status: .needsInput,
                    latestMessage: "Can I run the database migration?",
                    lastActivity: now, blockedSince: now.addingTimeInterval(-240),
                    pid: 1234, host: .terminal(app: "iTerm2", tty: "ttys004")),
            Session(id: "stub-running",
                    projectPath: "/Users/you/Projects/web", displayName: "web",
                    source: .desktop, status: .running,
                    latestMessage: "Refactoring the router…",
                    lastActivity: now, blockedSince: nil,
                    pid: 5678, host: .desktop(bundleID: "com.anthropic.claudefordesktop")),
        ]
    }

    public func start() {}
    public func stop() {}
}
