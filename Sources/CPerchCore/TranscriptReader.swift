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
// `sessionId` and `cwd` are not carried in the transcript body, so the caller
// (SessionMerger / SessionStore) supplies them — it already knows them from the
// registry or the projects/<enc-cwd>/<sessionId>.jsonl path.
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
            cwd: cwd,
            lastRole: message?["role"] as? String,
            lastStopReason: message?["stop_reason"] as? String,
            pendingToolUses: pending,
            lastText: latestAssistantText(in: real),
            lastActivity: modificationDate(of: url)
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

    private func modificationDate(of url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            ?? .distantPast
    }
}
