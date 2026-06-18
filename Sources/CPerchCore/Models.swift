import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// FROZEN v0 CONTRACT.
// All Phase-1 parallel tracks depend on these types. Do not change them without a
// contract review (it invalidates in-flight parallel work). See tasks/plan.md.
// ─────────────────────────────────────────────────────────────────────────────

/// The status cPerch shows for a session.
public enum DerivedStatus: String, Sendable, Codable {
    case running      // 🔵 actively working
    case needsInput   // 🟠 blocked, waiting on the human
    case concluded    // ✅ finished, or the process is gone
}

/// Where a session is hosted — informs how "jump" reaches it.
public enum SessionSource: String, Sendable, Codable {
    case cli          // a terminal `claude` session
    case desktop      // the Claude desktop app
    case background   // a bg / daemon-worker session
    case unknown
}

/// How to reach a session's host window for "jump" (never spawns a duplicate).
public enum HostRef: Sendable, Equatable {
    case terminal(app: String, tty: String)   // focus this tab via Apple Events
    case desktop(bundleID: String)             // activate the app
    case unknown
}

/// A unified Claude session as shown in cPerch. Produced by SessionMerger (P1-G).
public struct Session: Identifiable, Sendable, Equatable {
    public let id: String              // Claude sessionId (UUID)
    public var projectPath: String     // working directory (cwd)
    public var displayName: String     // project basename or AI-generated title
    public var source: SessionSource
    public var status: DerivedStatus
    public var latestMessage: String?  // inline preview
    public var lastActivity: Date
    public var blockedSince: Date?     // entered needsInput at — drives "blocked Nm"
    public var pid: Int?
    public var host: HostRef

    public init(id: String, projectPath: String, displayName: String, source: SessionSource,
                status: DerivedStatus, latestMessage: String?, lastActivity: Date,
                blockedSince: Date?, pid: Int?, host: HostRef) {
        self.id = id
        self.projectPath = projectPath
        self.displayName = displayName
        self.source = source
        self.status = status
        self.latestMessage = latestMessage
        self.lastActivity = lastActivity
        self.blockedSince = blockedSince
        self.pid = pid
        self.host = host
    }
}

/// Aggregate state for the menu-bar dot. Reflects LIVE state only — a concluded
/// session never turns the dot orange. Most-urgent-wins.
public enum AggregateState: String, Sendable {
    case needsInput   // 🟠 someone needs you
    case running      // 🔵 working
    case idle         // dim — nothing live needs you

    public init(sessions: [Session]) {
        if sessions.contains(where: { $0.status == .needsInput }) {
            self = .needsInput
        } else if sessions.contains(where: { $0.status == .running }) {
            self = .running
        } else {
            self = .idle
        }
    }
}
