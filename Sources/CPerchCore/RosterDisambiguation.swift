import Foundation

// cPerch — roster disambiguation (Track U / finding L2, decision DD-L2).
//
// Two sessions in the same project render IDENTICAL names: `displayName` is the cwd
// basename (or, once Track T lands it, an AI title), so a babysitter watching two
// `claude-toolbar-mac` sessions sees two visually identical rows and can't tell which is
// which. When ≥2 *visible* rows share a `displayName`, the roster shows a muted secondary
// label — a short relative time ("2m ago") — so the rows are tellable apart.
//
// This is the PURE, Foundation-only home for that logic (the SwiftUI view stays thin and
// just renders the map): given the ordered sessions and a clock, it returns the label per
// colliding session id. Uniquely-named sessions get no entry. Kept here (not in the view)
// so it's unit-testable — see RosterDisambiguationTests (AC-L2.3).

/// Computes the per-session disambiguation labels for a roster snapshot.
public enum RosterDisambiguation {

    /// For every `displayName` shared by ≥2 sessions, returns a short relative-time label
    /// (keyed by `Session.ID`) so the colliding rows can be told apart. Sessions whose
    /// `displayName` is unique in `sessions` are absent from the result.
    ///
    /// Relative time is coarse and human ("just now" / "2m ago" / "1h ago" / "3d ago"),
    /// computed against `now`. If two colliding sessions would produce the *same*
    /// relative-time string (e.g. both last active ~2m ago), a short id-based suffix is
    /// appended to each so the labels still differ — the row's reason for being shown is
    /// to disambiguate, so the labels must never be identical.
    public static func labels(for sessions: [Session], now: Date) -> [Session.ID: String] {
        // 1. Find the displayNames that collide (shared by ≥2 sessions).
        var countByName: [String: Int] = [:]
        for session in sessions {
            countByName[session.displayName, default: 0] += 1
        }
        let collidingNames = Set(countByName.filter { $0.value >= 2 }.keys)
        guard !collidingNames.isEmpty else { return [:] }

        // 2. Base relative-time label for every colliding session.
        var result: [Session.ID: String] = [:]
        var idsByLabel: [String: [Session.ID]] = [:]   // base label → colliding ids
        for session in sessions where collidingNames.contains(session.displayName) {
            let label = relativeTime(from: session.lastActivity, to: now)
            result[session.id] = label
            idsByLabel[label, default: []].append(session.id)
        }

        // 3. Tiebreak: where two+ colliding sessions share a base label, append a short
        //    id-derived suffix so the labels are still distinct.
        for (label, ids) in idsByLabel where ids.count >= 2 {
            for id in ids {
                result[id] = "\(label) (\(shortID(id)))"
            }
        }

        return result
    }

    // MARK: - Helpers

    /// A coarse, human relative time: "just now" under a minute, then minutes, hours, days.
    /// Deliberately low-resolution — it's a glance-level disambiguator, not a clock.
    static func relativeTime(from past: Date, to now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(past))
        if seconds < 60 { return "just now" }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        let days = hours / 24
        return "\(days)d ago"
    }

    /// The first 4 characters of the id (a UUID/sessionId), as a last-resort tiebreak.
    /// Short ids are returned whole.
    static func shortID(_ id: Session.ID) -> String {
        String(id.prefix(4))
    }
}
