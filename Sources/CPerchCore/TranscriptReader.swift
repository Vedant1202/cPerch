import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// P1-C · TranscriptReader
//
// Reads a single Claude session transcript (`<sessionId>.jsonl`) and produces a
// `TranscriptSignal` (the frozen contract in SourceRecords.swift). Pure Foundation,
// read-only — cPerch never mutates ~/.claude.
//
// The logic mirrors the validated spike (spikes/session-status-scanner →
// `analyzeTranscript`): tail-read the last ~256 KB, parse newline-delimited JSON,
// keep only real user/assistant turns, then derive:
//   • lastRole / lastStopReason — from the message of the last real record,
//   • pendingToolUses           — tool_use ids with no matching tool_result,
//   • lastText                  — the latest assistant text block (preview),
//   • lastActivity              — the file's modification time.
//
// `sessionId` is not carried reliably enough to key on, so the caller supplies it.
// `cwd` HOWEVER is carried on every real record as an exact top-level field (D1 /
// DD-1): we read it from the last real record that has one and fall back to the
// caller-supplied `cwd` only when no record carries it. This matters because the
// recent-files path supplies a `decodeProjectDir`-mangled cwd that is also a join
// key in SessionMerger Pass 2 — echoing it would mis-bind hyphenated-dir sessions.
// ─────────────────────────────────────────────────────────────────────────────

public struct TranscriptReader: Sendable {

    /// Tail bytes read from the end of the transcript. A session's status only
    /// depends on the most recent turns, so we never read the whole file.
    public let maxTailBytes: UInt64

    public init(maxTailBytes: UInt64 = 262_144) {   // 256 KB, as in the spike
        self.maxTailBytes = maxTailBytes
    }

    /// Read the transcript at `path` and derive its signal. Returns `nil` when the
    /// file is missing or unreadable (e.g. a registry entry whose transcript hasn't
    /// landed yet) — callers treat the absence as "no transcript info".
    public func read(path: String, sessionId: String, cwd: String) -> TranscriptSignal? {
        let url = URL(fileURLWithPath: path)
        guard let tail = readTail(url) else { return nil }

        let real = realRecords(in: tail)
        let pending = pendingToolUses(in: real)
        let last = real.last
        let message = last?["message"] as? [String: Any]

        return TranscriptSignal(
            sessionId: sessionId,
            cwd: recordCwd(in: real) ?? cwd,   // transcript's own cwd wins; argument is fallback
            lastRole: message?["role"] as? String,
            lastStopReason: message?["stop_reason"] as? String,
            pendingToolUses: pending,
            lastText: previewText(in: real),
            // D6 / DD-D6: the last real record's own `timestamp` is the precise activity
            // instant; it's robust to non-Claude touches (editor open, backup) that move
            // the file's mtime. Fall back to mtime when no record carries a parseable one.
            lastActivity: lastRecordActivity(in: real) ?? modificationDate(of: url),
            // L2 / DD-L2: the AI-generated title rides as a separate `ai-title` meta
            // record, which realRecords() filters out — so scan the raw tail for it.
            aiTitle: aiTitle(in: tail)
        )
    }

    // MARK: - Tail read

    private func readTail(_ url: URL) -> String? {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? fh.close() }
        guard let size = try? fh.seekToEnd() else { return nil }
        let start = size > maxTailBytes ? size - maxTailBytes : 0
        try? fh.seek(toOffset: start)
        guard let data = try? fh.readToEnd() else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - Parsing & filtering

    /// Meta `type`s that are not conversation turns. Everything that isn't a real
    /// `user`/`assistant` record is ignored anyway (allowlist below), but these are
    /// the shapes observed in the wild — listed for clarity:
    /// mode · last-prompt · ai-title · agent-name · permission-mode · system ·
    /// file-history-snapshot (also: attachment, queue-operation, …).

    /// Keep only real conversation turns: top-level `type` is `user` or `assistant`,
    /// and the record is not a sidechain (sub-agent) turn.
    private func realRecords(in tail: String) -> [[String: Any]] {
        var real: [[String: Any]] = []
        for line in tail.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = line.data(using: .utf8),
                  let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            else { continue }
            let type = object["type"] as? String
            guard type == "user" || type == "assistant" else { continue }
            if isSidechain(object) { continue }
            real.append(object)
        }
        return real
    }

    /// `isSidechain == true` may sit at the top level or inside `message`.
    private func isSidechain(_ object: [String: Any]) -> Bool {
        if (object["isSidechain"] as? Bool) == true { return true }
        if let message = object["message"] as? [String: Any],
           (message["isSidechain"] as? Bool) == true { return true }
        return false
    }

    private func contentBlocks(_ object: [String: Any]) -> [[String: Any]] {
        ((object["message"] as? [String: Any])?["content"] as? [[String: Any]]) ?? []
    }

    // MARK: - Derivations

    /// The transcript-owned working directory: the top-level `cwd` of the last real
    /// record that carries one (D1 / DD-1). Real Claude records all carry an exact
    /// `cwd`; reading it here lets the merger join on the authoritative path instead
    /// of a lossy `decodeProjectDir` guess. Returns nil when no record has a `cwd`
    /// (e.g. a synthetic/legacy transcript), in which case the caller's fallback is used.
    private func recordCwd(in real: [[String: Any]]) -> String? {
        for object in real.reversed() {
            if let cwd = object["cwd"] as? String, !cwd.isEmpty { return cwd }
        }
        return nil
    }

    /// Count tool_use ids that have no matching tool_result `tool_use_id` — i.e.
    /// tool calls still awaiting a result (the agent is executing, or is parked
    /// waiting on the human to approve them).
    private func pendingToolUses(in real: [[String: Any]]) -> Int {
        var used = Set<String>()
        var resolved = Set<String>()
        for object in real {
            for block in contentBlocks(object) {
                switch block["type"] as? String {
                case "tool_use":
                    if let id = block["id"] as? String { used.insert(id) }
                case "tool_result":
                    if let id = block["tool_use_id"] as? String { resolved.insert(id) }
                default:
                    break
                }
            }
        }
        return used.subtracting(resolved).count
    }

    /// The roster preview text, with the L3 / DD-L3 fallback chain: the latest
    /// assistant text block (the normal case) → the latest user text (e.g. the turn
    /// ended on a pure tool_use with no assistant prose) → a `Running <tool>…` summary
    /// of the last pending tool (e.g. the agent is mid-tool with no text at all) →
    /// nil only as a last resort (RosterView already hides empty rows). The fallback
    /// keeps a row from rendering blank when there's no assistant prose to show.
    private func previewText(in real: [[String: Any]]) -> String? {
        if let assistant = latestAssistantText(in: real) { return assistant }
        if let user = latestUserText(in: real) { return user }
        if let tool = lastPendingToolName(in: real) { return "Running \(tool)…" }
        return nil
    }

    /// The most recent non-empty assistant text block — the inline preview.
    private func latestAssistantText(in real: [[String: Any]]) -> String? {
        for object in real.reversed() {
            guard let message = object["message"] as? [String: Any],
                  (message["role"] as? String) == "assistant" else { continue }
            for block in (message["content"] as? [[String: Any]]) ?? [] {
                if (block["type"] as? String) == "text",
                   let text = block["text"] as? String, !text.isEmpty {
                    return text
                }
            }
        }
        return nil
    }

    /// The most recent non-empty user text block (L3 fallback). User content can be a
    /// plain string or the structured content-block array; handle both. A user turn
    /// often also carries tool_result blocks — we only want the human's typed text.
    private func latestUserText(in real: [[String: Any]]) -> String? {
        for object in real.reversed() {
            guard let message = object["message"] as? [String: Any],
                  (message["role"] as? String) == "user" else { continue }
            // Older/simple shape: content is a bare string.
            if let text = message["content"] as? String, !text.isEmpty { return text }
            for block in (message["content"] as? [[String: Any]]) ?? [] {
                if (block["type"] as? String) == "text",
                   let text = block["text"] as? String, !text.isEmpty {
                    return text
                }
            }
        }
        return nil
    }

    /// The `name` of the last pending tool_use (L3 fallback): scan all tool_use ids
    /// that have no matching tool_result, then return the name of the latest such call
    /// in the tail. Used to render `Running <tool>…` when there's no prose at all.
    private func lastPendingToolName(in real: [[String: Any]]) -> String? {
        var resolved = Set<String>()
        for object in real {
            for block in contentBlocks(object) where (block["type"] as? String) == "tool_result" {
                if let id = block["tool_use_id"] as? String { resolved.insert(id) }
            }
        }
        for object in real.reversed() {
            for block in contentBlocks(object).reversed() where (block["type"] as? String) == "tool_use" {
                guard let id = block["id"] as? String, !resolved.contains(id) else { continue }
                if let name = block["name"] as? String, !name.isEmpty { return name }
            }
        }
        return nil
    }

    /// The AI-generated session title (L2 / DD-L2). The title rides as a meta record
    /// `{"type":"ai-title","aiTitle":"…","sessionId":"…"}`, which `realRecords` drops,
    /// so we scan the RAW tail lines here. The title can be regenerated as the
    /// conversation evolves, so we take the LAST `ai-title` record in the tail. Returns
    /// nil when no such record is present (the basename fallback then applies upstream).
    private func aiTitle(in tail: String) -> String? {
        var title: String? = nil
        for line in tail.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = line.data(using: .utf8),
                  let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  (object["type"] as? String) == "ai-title"
            else { continue }
            if let value = object["aiTitle"] as? String, !value.isEmpty {
                title = value   // keep scanning; the last one wins
            }
        }
        return title
    }

    private func modificationDate(of url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            ?? .distantPast
    }

    // MARK: - D6 · record timestamp

    /// The parsed top-level `timestamp` of the last real record that carries one
    /// (DD-D6). Real Claude records stamp each turn with an ISO-8601 instant; using
    /// it makes `lastActivity` precise and immune to non-Claude file touches. Returns
    /// nil when no real record has a parseable `timestamp`, so the caller can fall
    /// back to the file's mtime (the prior behavior).
    private func lastRecordActivity(in real: [[String: Any]]) -> Date? {
        for object in real.reversed() {
            if let raw = object["timestamp"] as? String,
               let date = TranscriptReader.parseTimestamp(raw) {
                return date
            }
        }
        return nil
    }

    /// Parse an ISO-8601 timestamp as written in Claude transcripts. The wild data
    /// uses fractional seconds with a `Z` (e.g. `2026-06-18T20:29:53.698Z`), but a
    /// single `ISO8601DateFormatter` can't accept BOTH fractional and whole-second
    /// forms — `.withFractionalSeconds` makes the fraction mandatory. So we try the
    /// fractional formatter first, then the plain one (which also handles numeric
    /// offsets like `+02:00`). Returns nil on anything unparseable (garbage, empty).
    public static func parseTimestamp(_ s: String) -> Date? {
        if let date = iso8601Fractional.date(from: s) { return date }
        return iso8601Plain.date(from: s)
    }

    /// ISO-8601 with fractional seconds (the common Claude-transcript shape).
    private static let iso8601Fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// ISO-8601 without fractional seconds; also accepts numeric offsets (`+02:00`).
    private static let iso8601Plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}
