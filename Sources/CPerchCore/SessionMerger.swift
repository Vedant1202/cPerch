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

    /// Pick the winner between two registry entries that share a (canonical) sessionId
    /// (D5). A duplicate happens when a crashed session's lingering `<pid>.json` coexists
    /// with the live one, or when an alias collapses two source entries. Prefer the entry
    /// whose pid is currently LIVE; if neither (or both) is live, prefer the newest
    /// `startedAt` (now available from D3). A nil `startedAt` loses to any real instant,
    /// and ties hold the incumbent (deterministic). Replaces the old lexical-filename
    /// order, which could let a dead entry shadow the live one.
    static func preferRegistryEntry(_ a: RegistryEntry, _ b: RegistryEntry,
                                    livePids: Set<Int>) -> RegistryEntry {
        let aLive = livePids.contains(a.pid)
        let bLive = livePids.contains(b.pid)
        if aLive != bLive { return aLive ? a : b }   // exactly one live → it wins
        // Both or neither live → newest startedAt wins; nil sorts oldest; tie keeps `a`.
        let aStart = a.startedAt ?? .distantPast
        let bStart = b.startedAt ?? .distantPast
        return bStart > aStart ? b : a
    }

    /// Merge the three per-source record streams into unified sessions.
    ///
    /// - Parameters:
    ///   - processes:   live OS process records (P1-A). Presence ⇒ the bound session is alive.
    ///   - registry:    `~/.claude/sessions/*.json` entries (P1-B) — the pid→sessionId bridge.
    ///   - transcripts: per-session transcript signals (P1-C) — preview + activity + fallback status.
    ///   - now:         injected clock for deterministic freshness (defaults to `Date()`).
    ///   - aliases:     optional sessionId-canonicalization map (D9 seam) — `cli → local_…`
    ///                  once the desktop source lands. Default empty ⇒ no behavior change.
    /// - Returns: sessions keyed by `sessionId`, sorted needs-you-first then most-recent.
    public static func merge(processes: [ProcessRecord],
                             registry: [RegistryEntry],
                             transcripts: [TranscriptSignal],
                             now: Date = Date(),
                             aliases: [String: String] = [:]) -> [Session] {

        // The set of pids currently alive — used both as the liveness signal and, for D5,
        // to break a duplicate-sessionId registry tie toward the entry that's actually live.
        let livePids = Set(processes.map(\.pid))

        // Index the inputs by their (canonical) join keys. SessionIds are canonicalized
        // through `aliases` first (D9) so an aliased `cli`/`local_` pair collapses to one
        // session. With empty aliases this is the identity — output is unchanged.
        let transcriptsById = Dictionary(
            transcripts.map { (canonicalSessionId($0.sessionId, aliases: aliases), $0) },
            uniquingKeysWith: { _, new in new })   // later capture supersedes an earlier one

        // Registry index (D5): on a duplicate sessionId, keep the entry whose pid is LIVE,
        // else the one with the newest `startedAt`. Lexical filename order (the old
        // `Dictionary(uniquingKeysWith: { _, new in new })` over `names.sorted()`) was
        // arbitrary — a dead lingering `<pid>.json` could shadow the live one.
        var registryById: [String: RegistryEntry] = [:]
        for e in registry {
            let key = canonicalSessionId(e.sessionId, aliases: aliases)
            if let existing = registryById[key] {
                registryById[key] = preferRegistryEntry(existing, e, livePids: livePids)
            } else {
                registryById[key] = e
            }
        }

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
                    // Canonicalize so the bind lands on the same key the session is built
                    // under (D9) — an aliased entry must mark its canonical session alive.
                    pidForSession[canonicalSessionId(entry.sessionId, aliases: aliases)] = p.pid
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
        // The cwd compare is NORMALIZED on both sides (D4): `/tmp/x` vs `/private/tmp/x`,
        // a trailing slash, or `.`/`..` no longer block a real match, while distinct dirs
        // still don't collide. SessionIds are canonicalized (D9) to key `pidForSession`
        // consistently with the registry pass and the session-build loop.
        let claimable = transcripts
            .filter { pidForSession[canonicalSessionId($0.sessionId, aliases: aliases)] == nil }
            .sorted { $0.lastActivity > $1.lastActivity }
        for p in unregistered {
            guard let cwd = p.cwd else { continue }
            let normCwd = normalizedPath(cwd)
            if let match = claimable.first(where: {
                normalizedPath($0.cwd) == normCwd
                    && pidForSession[canonicalSessionId($0.sessionId, aliases: aliases)] == nil
            }) {
                pidForSession[canonicalSessionId(match.sessionId, aliases: aliases)] = p.pid
            }
        }

        // ── Collapse resumed/forked lineage (B1) ───────────────────────────────
        // A live process that resumed from an ancestor session (cmdline `--resume <id>`,
        // typically with `--fork-session`) supersedes that ancestor — so the forked
        // conversation is ONE row, not one per transcript left in the cwd. Map each bound
        // live pid → its `resumedFrom`, and drop the ancestor id when its descendant is live.
        let processByPid = Dictionary(processes.map { ($0.pid, $0) }, uniquingKeysWith: { a, _ in a })
        var supersededIds: Set<String> = []
        for (sessionId, pid) in pidForSession {
            guard let from = processByPid[pid]?.resumedFrom else { continue }
            let ancestor = canonicalSessionId(from, aliases: aliases)
            if ancestor != sessionId { supersededIds.insert(ancestor) }
        }

        // ── Build one Session per known sessionId ──────────────────────────────
        // The universe of sessions is every id seen in the registry or a transcript, minus
        // any superseded resume-ancestor (B1).
        let allIds = Set(registryById.keys).union(transcriptsById.keys).subtracting(supersededIds)

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
                displayName: sig?.aiTitle ?? displayName(for: cwd),   // L2: AI title wins, basename fallback
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
        case "end_turn", "stop_sequence", "max_tokens":
            // The turn finished cleanly — but if the assistant's parting text was an
            // open question / permission request, the ball is in the human's court
            // (L1). We're already past the `!alive` guard, so a dead session can never
            // reach here (AC-L1.3). Bias to few false positives: only a clear question
            // flips to needsInput, else the task is done (CLAUDE.md — a false nag hurts).
            return looksLikeAwaitingUser(s.lastText) ? .needsInput : .concluded
        default: return s.lastRole == "user" ? (stalled ? .needsInput : .running) : .concluded
        }
    }

    /// Heuristic: does this assistant text read as *waiting on the human*? True when the
    /// trimmed text ends with `?`, or contains one of a SMALL curated set of permission /
    /// question phrases. Deliberately conservative (L1 / CLAUDE.md): a false `needsInput`
    /// nags the user, so we only trip on clear asks — a rhetorical `?` mid-sentence on a
    /// finished statement must NOT match (hence the *trailing* `?` test, not "contains ?").
    static func looksLikeAwaitingUser(_ text: String?) -> Bool {
        guard let raw = text else { return false }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        if trimmed.hasSuffix("?") { return true }

        // Curated permission/question phrases, matched at WORD BOUNDARIES so a bare
        // substring can't nag: "confirm" hits "please confirm" but not "confirmed",
        // "should i" hits "should i deploy" but not "should ignore"/"should investigate".
        let phrases = [
            "let me know", "would you like", "should i", "shall i",
            "do you want", "which would you", "want me to", "confirm", "approve",
        ]
        let lower = trimmed.lowercased()
        return phrases.contains { containsWordBounded(lower, $0) }
    }

    /// `needle` occurs in `haystack` flanked by non-letters (or the string ends) — i.e.
    /// word-bounded containment. This is the guard that keeps `looksLikeAwaitingUser` from
    /// tripping on finished statements: "confirmed"/"approved"/"should investigate" must
    /// NOT match "confirm"/"approve"/"should i" (L1 / CLAUDE.md: a false needsInput nags).
    static func containsWordBounded(_ haystack: String, _ needle: String) -> Bool {
        guard !needle.isEmpty else { return false }
        var from = haystack.startIndex
        while let r = haystack.range(of: needle, range: from..<haystack.endIndex) {
            let leftOK = r.lowerBound == haystack.startIndex
                || !haystack[haystack.index(before: r.lowerBound)].isLetter
            let rightOK = r.upperBound == haystack.endIndex
                || !haystack[r.upperBound].isLetter
            if leftOK && rightOK { return true }
            from = haystack.index(after: r.lowerBound)
        }
        return false
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

    /// Classify a session's host (v0.3): Terminal (`.cli`) vs Claude app (`.desktop`) vs
    /// `.background` vs `.unknown`. Daemon/`bg` kinds are Background whatever the entrypoint.
    /// Otherwise the registry `entrypoint` is the DIRECT signal (`cli` → Terminal,
    /// `claude-desktop` → Claude app) and is preferred over the tty-derived guess — which
    /// mislabels a *terminal* session launched via the desktop-bundled `claude` binary (no
    /// tty) as the desktop app. When `entrypoint` is absent (older CLIs), fall back to the
    /// prior kind+tty derivation so nothing regresses.
    static func resolveSource(entry: RegistryEntry?, host: HostRef) -> SessionSource {
        // 1) Daemon/background kinds first — neither a terminal nor the desktop app.
        switch entry?.kind {
        case "bg", "daemon", "daemon-worker": return .background
        default: break
        }
        // 2) entrypoint is the direct Terminal-vs-Claude-app signal — prefer it.
        switch entry?.entrypoint {
        case "cli":            return .cli
        case "claude-desktop": return .desktop
        default: break
        }
        // 3) No entrypoint → fall back to the kind + tty derivation.
        switch entry?.kind {
        case "desktop": return .desktop
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

    /// Canonicalize a filesystem path for joining (D4). Resolves symlinks (so `/tmp/x`
    /// and `/private/tmp/x` — `/tmp` is a macOS symlink — compare equal), standardizes
    /// (`.`/`..`), and strips any trailing `/`. Used on BOTH sides of the Pass-2 cwd
    /// compare so equivalent spellings of the same directory bind, while genuinely
    /// distinct directories still don't collide. Empty stays empty.
    static func normalizedPath(_ p: String) -> String {
        guard !p.isEmpty else { return p }
        let resolved = URL(fileURLWithPath: p).standardizedFileURL
            .resolvingSymlinksInPath().path
        if resolved.count > 1, resolved.hasSuffix("/") {
            return String(resolved.dropLast())
        }
        return resolved
    }

    /// Resolve a sessionId through an alias map (D9 seam). Returns the canonical id when
    /// `aliases` maps it, else the id unchanged. The forward-looking use is a
    /// `cliSessionId → desktop local_… id` map (populated once the desktop source lands)
    /// that collapses the same conversation seen from two sources to one row. With the
    /// default-empty map this is the identity, so present-day output is unchanged.
    static func canonicalSessionId(_ id: String, aliases: [String: String]) -> String {
        aliases[id] ?? id
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
