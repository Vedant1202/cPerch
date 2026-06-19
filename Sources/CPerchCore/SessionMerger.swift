import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// P1-G · SessionMerger — the dedup/merge + status-resolution brain.
//
// Folds the three frozen source-record types into the unified `[Session]` the rest
// of cPerch consumes. Pure (Foundation-only, no I/O, no global state): the readers
// (A/B/C) gather the records; this function decides the truth.
//
// Spine = `sessionId` (SPEC §3). The registry bridges pid → sessionId; process-scan
// PIDs join via that bridge, falling back to cwd + recency for unregistered processes.
// Liveness comes from whether a live process is bound; status is resolved by
// reliability (registry `status` → transcript heuristic — see the spike's deriveStatus).
// ─────────────────────────────────────────────────────────────────────────────

public enum SessionMerger {

    /// A session is flagged needs-input via the transcript fallback only once it has been
    /// quiet at least this long — a busy turn or long tool call can stay silent for a
    /// while, so we avoid a premature "needs you" (matches the spike's threshold).
    static let stalledThreshold: TimeInterval = 120

    /// How far a live process's start time may diverge from a registry entry's
    /// `startedAt` before we treat the pid as RECYCLED rather than the session's own
    /// process (D3 / DD-3). macOS reuses PIDs: a crashed session's lingering `<pid>.json`
    /// plus a reused pid would otherwise show a dead session as alive and aim "jump" at
    /// the wrong window. A reused pid's new process starts minutes–hours after the dead
    /// session's `startedAt`, so a loose tolerance catches reuse with ~zero false rejects.
    static let pidReuseTolerance: TimeInterval = 120

    /// Whether a registry-pid bind can be trusted — i.e. the live process holding `pid`
    /// is plausibly the same process that registry `entry` recorded, not a PID-reuse
    /// impostor (D3). Pure; called by Pass 1 before binding.
    ///
    /// Returns `true` when EITHER start time is unknown (`nil`) — we never regress on
    /// missing data (DD-3) — else only when the two instants agree within `tolerance`.
    static func bindIsTrustworthy(process: ProcessRecord, entry: RegistryEntry,
                                  tolerance: TimeInterval = pidReuseTolerance) -> Bool {
        guard let pStart = process.startTime, let rStart = entry.startedAt else {
            return true   // unknown start → trust (no regression on missing data)
        }
        return abs(pStart.timeIntervalSince(rStart)) <= tolerance
    }

    /// Merge the three per-source record streams into unified sessions.
    ///
    /// - Parameters:
    ///   - processes:   live OS process records (P1-A). Presence ⇒ the bound session is alive.
    ///   - registry:    `~/.claude/sessions/*.json` entries (P1-B) — the pid→sessionId bridge.
    ///   - transcripts: per-session transcript signals (P1-C) — preview + activity + fallback status.
    ///   - now:         injected clock for deterministic freshness (defaults to `Date()`).
    /// - Returns: sessions keyed by `sessionId`, sorted needs-you-first then most-recent.
    public static func merge(processes: [ProcessRecord],
                             registry: [RegistryEntry],
                             transcripts: [TranscriptSignal],
                             now: Date = Date()) -> [Session] {

        // Index the inputs by their join keys. `last` wins on duplicate ids/pids so a
        // later (more recently captured) record supersedes an earlier one.
        let transcriptsById = Dictionary(transcripts.map { ($0.sessionId, $0) },
                                         uniquingKeysWith: { _, new in new })
        let registryById = Dictionary(registry.map { ($0.sessionId, $0) },
                                      uniquingKeysWith: { _, new in new })
        let registryByPid = Dictionary(registry.map { ($0.pid, $0) },
                                       uniquingKeysWith: { _, new in new })

        // ── Bridge process records → sessionId ──────────────────────────────────
        // A process maps to a session either directly (its pid is in the registry) or,
        // for an unregistered process, by matching a transcript on cwd + recency.
        var pidForSession: [String: Int] = [:]   // sessionId → live pid

        // Pass 1: registered processes bind their session directly — but only when the
        // bind is trustworthy (D3 / DD-4). macOS recycles PIDs, so a registry pid that's
        // now held by a process with a mismatched start time is a reuse impostor: the
        // real session is gone. We DROP such a bind — and deliberately do NOT fall it
        // through to `unregistered` (it isn't our session, so it must not claim a
        // transcript by cwd in Pass 2 either) — so the session resolves `concluded`.
        var unregistered: [ProcessRecord] = []
        for p in processes {
            if let entry = registryByPid[p.pid] {
                if bindIsTrustworthy(process: p, entry: entry) {
                    pidForSession[entry.sessionId] = p.pid
                }
                // else: confident PID-reuse mismatch → drop the bind, don't re-claim.
            } else {
                unregistered.append(p)
            }
        }

        // Pass 2: each unregistered process claims the most-recently-active transcript
        // sharing its cwd that isn't already bound. Newest-process-first keeps the
        // assignment stable when several compete for the same directory (cwd collision —
        // a documented best-effort limitation: we attach liveness to the freshest session).
        let claimable = transcripts
            .filter { pidForSession[$0.sessionId] == nil }   // not already bound via registry
            .sorted { $0.lastActivity > $1.lastActivity }
        for p in unregistered {
            guard let cwd = p.cwd else { continue }
            if let match = claimable.first(where: { $0.cwd == cwd && pidForSession[$0.sessionId] == nil }) {
                pidForSession[match.sessionId] = p.pid
            }
        }

        // ── Build one Session per known sessionId ──────────────────────────────
        // The universe of sessions is every id seen in the registry or a transcript.
        let allIds = Set(registryById.keys).union(transcriptsById.keys)

        let sessions = allIds.map { id -> Session in
            let entry = registryById[id]
            let sig = transcriptsById[id]
            let livePid = pidForSession[id]
            let alive = livePid != nil

            // cwd: registry is authoritative; else the transcript's.
            let cwd = entry?.cwd ?? sig?.cwd ?? ""

            let status = deriveStatus(registryStatus: entry?.status, alive: alive, sig: sig, now: now)
            let host = resolveHost(entry: entry, livePid: livePid, processes: processes)
            let source = resolveSource(entry: entry, host: host)

            return Session(
                id: id,
                projectPath: cwd,
                displayName: displayName(for: cwd),
                source: source,
                status: status,
                latestMessage: sig?.lastText,
                lastActivity: sig?.lastActivity ?? .distantPast,
                blockedSince: nil,                 // the store sets this over time
                pid: livePid,
                host: host
            )
        }

        return sortNeedsYouFirst(sessions)
    }

    // MARK: - Status resolution (registry > transcript), per SPEC §3 / spike deriveStatus

    static func deriveStatus(registryStatus: String?, alive: Bool,
                             sig: TranscriptSignal?, now: Date) -> DerivedStatus {
        if !alive { return .concluded }                         // process gone → session ended

        switch registryStatus {                                 // trust Claude's own field first
        case "busy", "shell": return .running
        case "waiting":       return .needsInput
        case "idle":
            // Parked mid-tool ⇒ wants you; otherwise nothing's pending ⇒ done.
            if let s = sig, s.pendingToolUses > 0 { return .needsInput }
            return .concluded
        default: break
        }

        // No status field (e.g. older desktop app): infer from the transcript. Timing is
        // fuzzy, so only flag needs-input once quiet long enough to almost certainly be
        // blocked on the human.
        guard let s = sig else { return .concluded }
        let stalled = now.timeIntervalSince(s.lastActivity) > stalledThreshold
        if s.pendingToolUses > 0 { return stalled ? .needsInput : .running }
        switch s.lastStopReason {
        case "tool_use": return stalled ? .needsInput : .running
        case "end_turn", "stop_sequence", "max_tokens": return .concluded
        default: return s.lastRole == "user" ? (stalled ? .needsInput : .running) : .concluded
        }
    }

    // MARK: - Host + source resolution

    /// Where to send "jump". A tty (from the live process) ⇒ a terminal tab. No tty but a
    /// desktop/interactive kind ⇒ activate the Claude desktop app. Otherwise unknown.
    static func resolveHost(entry: RegistryEntry?, livePid: Int?,
                            processes: [ProcessRecord]) -> HostRef {
        if let pid = livePid, let tty = processes.first(where: { $0.pid == pid })?.tty, !tty.isEmpty {
            // App is unknown at the core layer (resolving tty → owning terminal is the
            // Jumper's job, P1-E); a generic "Terminal" is the safe placeholder.
            return .terminal(app: "Terminal", tty: tty)
        }
        switch entry?.kind {
        case "interactive", "desktop":
            return .desktop(bundleID: "com.anthropic.claudefordesktop")
        default:
            return .unknown
        }
    }

    static func resolveSource(entry: RegistryEntry?, host: HostRef) -> SessionSource {
        switch entry?.kind {
        case "bg", "daemon", "daemon-worker": return .background
        case "desktop":                       return .desktop
        case "interactive":
            // An interactive session reached via a terminal tab is a CLI session;
            // without a tty it's the desktop app.
            if case .terminal = host { return .cli }
            return .desktop
        default:
            // Unknown kind: a tty still tells us it's a terminal session.
            if case .terminal = host { return .cli }
            return .unknown
        }
    }

    // MARK: - Presentation helpers

    static func displayName(for cwd: String) -> String {
        let name = (cwd as NSString).lastPathComponent
        return name.isEmpty ? cwd : name
    }

    /// Needs-you-first (needsInput → running → concluded), then most-recent activity.
    static func sortNeedsYouFirst(_ sessions: [Session]) -> [Session] {
        func rank(_ s: DerivedStatus) -> Int {
            switch s {
            case .needsInput: return 0
            case .running:    return 1
            case .concluded:  return 2
            }
        }
        return sessions.sorted { a, b in
            let ra = rank(a.status), rb = rank(b.status)
            if ra != rb { return ra < rb }
            if a.lastActivity != b.lastActivity { return a.lastActivity > b.lastActivity }
            return a.id < b.id   // stable tiebreak
        }
    }
}
