import Foundation

// cPerch — VoiceOver string builders (v0.5 A4). cPerch is an *announcer* app, so the
// spoken text is product surface — kept pure here and unit-tested. The App layer applies
// these to the roster rows (`accessibilityLabel(for:)`) and the menu-bar item's live value
// (`menuBarAccessibilityValue(...)`).

/// A row's spoken announcement, e.g. "api, needs input, blocked 4 minutes. Latest: Can I run
/// the migration?". The blocked clause appears only for needsInput; the preview only when present.
public func accessibilityLabel(for s: Session, now: Date) -> String {
    var label = "\(s.displayName), \(statusPhrase(s.status))"
    if s.status == .needsInput {
        label += ", blocked \(spokenWait(since: s.blockedSince ?? s.lastActivity, now: now))"
    }
    if let preview = s.latestMessage, !preview.isEmpty {
        label += ". Latest: \(preview)"
    }
    return label
}

/// The menu-bar item's spoken value — the live, most-urgent summary.
public func menuBarAccessibilityValue(aggregate: AggregateState,
                                      needsInputCount: Int, runningCount: Int) -> String {
    switch aggregate {
    case .needsInput:
        return needsInputCount == 1 ? "1 session needs you" : "\(needsInputCount) sessions need you"
    case .running:
        return "\(runningCount) running"
    case .idle:
        return "all quiet"
    }
}

/// Status spoken as words (the enum raw value "needsInput" would mis-read).
private func statusPhrase(_ status: DerivedStatus) -> String {
    switch status {
    case .needsInput: return "needs input"
    case .running:    return "running"
    case .concluded:  return "concluded"
    }
}

/// A spoken relative wait ("just now" / "1 minute" / "4 minutes" / "1 hour 5 minutes") — the
/// VoiceOver counterpart to the roster's terse "blocked Nm" label.
func spokenWait(since: Date, now: Date) -> String {
    let mins = Int(max(0, now.timeIntervalSince(since)) / 60)
    if mins < 1 { return "just now" }
    if mins < 60 { return "\(mins) minute\(mins == 1 ? "" : "s")" }
    let h = mins / 60, r = mins % 60
    let hours = "\(h) hour\(h == 1 ? "" : "s")"
    return r == 0 ? hours : "\(hours) \(r) minute\(r == 1 ? "" : "s")"
}
