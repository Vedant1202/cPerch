import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// FROZEN v0 CONTRACT — raw per-source records.
// Each Phase-1 reader produces one of these; SessionMerger (P1-G) merges them
// into [Session]. Freezing these lets A/B/C/G be built in parallel.
//
// Post-v0 (dedup-hardening Phase 0): extended ADDITIVELY — `ProcessRecord.startTime`
// and `RegistryEntry.startedAt` are new optional, nil-defaulted fields for the D3
// PID-reuse guard, so existing initializer call sites compile unchanged.
// See docs/specs/dedup-hardening-v0.1.md.
// ─────────────────────────────────────────────────────────────────────────────

/// From the OS process table — ProcessScanner (P1-A).
public struct ProcessRecord: Sendable, Equatable {
    public let pid: Int
    public let ppid: Int
    public let tty: String?       // e.g. "ttys004"; nil for GUI/daemon processes
    public let cwd: String?
    public let cpu: Double        // %CPU — busy-vs-idle corroboration
    public let startTime: Date?   // process start instant — the D3 PID-reuse guard; nil when unresolved

    public init(pid: Int, ppid: Int, tty: String?, cwd: String?, cpu: Double, startTime: Date? = nil) {
        self.pid = pid; self.ppid = ppid; self.tty = tty; self.cwd = cwd; self.cpu = cpu
        self.startTime = startTime
    }
}

/// From ~/.claude/sessions/<pid>.json — RegistryReader (P1-B).
public struct RegistryEntry: Sendable, Equatable {
    public let pid: Int
    public let sessionId: String
    public let cwd: String
    public let status: String?    // busy | shell | idle | waiting | nil (older versions omit it)
    public let kind: String?      // interactive | bg | daemon | daemon-worker
    public let version: String?
    public let startedAt: Date?   // session start instant (registry `startedAt`, epoch ms) — D3 PID-reuse guard

    public init(pid: Int, sessionId: String, cwd: String, status: String?, kind: String?,
                version: String?, startedAt: Date? = nil) {
        self.pid = pid; self.sessionId = sessionId; self.cwd = cwd
        self.status = status; self.kind = kind; self.version = version
        self.startedAt = startedAt
    }
}

/// From a session transcript .jsonl — TranscriptReader (P1-C).
public struct TranscriptSignal: Sendable, Equatable {
    public let sessionId: String
    public let cwd: String
    public let lastRole: String?         // "user" | "assistant"
    public let lastStopReason: String?   // "tool_use" | "end_turn" | "stop_sequence" | ...
    public let pendingToolUses: Int      // tool_use records without a matching tool_result
    public let lastText: String?         // latest assistant text — preview
    public let lastActivity: Date        // transcript mtime / last record timestamp

    public init(sessionId: String, cwd: String, lastRole: String?, lastStopReason: String?,
                pendingToolUses: Int, lastText: String?, lastActivity: Date) {
        self.sessionId = sessionId; self.cwd = cwd; self.lastRole = lastRole
        self.lastStopReason = lastStopReason; self.pendingToolUses = pendingToolUses
        self.lastText = lastText; self.lastActivity = lastActivity
    }
}
