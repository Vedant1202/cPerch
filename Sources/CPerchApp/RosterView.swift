import SwiftUI
import CPerchCore

// cPerch — the dropdown roster (P1-D).
//
// A SwiftUI view, hosted from the NSStatusItem via NSPopover + NSHostingView
// (see MenuBarController). Renders the sessions published by a `SessionProviding`
// store: needs-you-first, each row a status dot + project name + latest-message
// preview + a "blocked Nm" wait label (needsInput only) + a Jump button.
//
// Styling follows docs/design/design-tokens.md — the Claude accent palette plus an
// Inter-ish UI font and a JetBrains-Mono-ish font for the message preview.

/// The roster's content. `sessions` is the current snapshot (the store sorts
/// needs-you-first; we re-sort defensively so the view is correct in isolation).
/// `onJump` is a placeholder until the real Jumper integrates in P3.
struct RosterView: View {
    let sessions: [Session]
    /// Responsive cap for the scrollable session list, set from the screen height by
    /// MenuBarController so the popover never grows to cover the whole display.
    var maxListHeight: CGFloat = 420
    /// Flat list (default) or collapsible source groups (Settings → View).
    var viewMode: RosterViewMode = .list
    var onJump: (Session) -> Void = { _ in }
    var onSettings: () -> Void = {}
    var onQuit: () -> Void = {}

    /// Collapsed source-group headers (by `SessionSource.rawValue`) for the grouped view.
    /// `@State` so it survives roster refreshes (SwiftUI preserves it across rootView updates).
    @State private var collapsedSources: Set<String> = []

    /// Needs-you-first: needsInput → running → concluded; within a bucket, the
    /// most recently active (or longest-blocked) first.
    private var ordered: [Session] {
        sessions.sorted { a, b in
            let ra = Self.rank(a.status), rb = Self.rank(b.status)
            if ra != rb { return ra < rb }
            return Self.sortDate(a) > Self.sortDate(b)
        }
    }

    private static func rank(_ status: DerivedStatus) -> Int {
        switch status {
        case .needsInput: return 0
        case .running:    return 1
        case .concluded:  return 2
        }
    }

    private static func sortDate(_ s: Session) -> Date {
        s.blockedSince ?? s.lastActivity
    }

    /// L2 (DD-L2): a muted secondary label per session whose `displayName` collides with
    /// another *visible* row, so same-project rows are tellable apart. Computed once from
    /// the ordered snapshot via the pure CPerchCore helper; uniquely-named rows get none.
    private var disambiguationLabels: [Session.ID: String] {
        RosterDisambiguation.labels(for: ordered, now: Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(TokenColors.divider)

            if ordered.isEmpty {
                emptyState
            } else {
                ScrollView {
                    switch viewMode {
                    case .list:            flatList
                    case .groupedBySource: groupedList
                    }
                }
                .frame(maxHeight: maxListHeight)
            }

            Divider().overlay(TokenColors.divider)
            footer
        }
        .frame(width: 340)
        .background(.background)
    }

    // MARK: - List layouts (flat vs grouped-by-source)

    private var flatList: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(ordered.enumerated()), id: \.element.id) { index, session in
                SessionRow(session: session,
                           disambiguator: disambiguationLabels[session.id],
                           onJump: onJump)
                if index < ordered.count - 1 {
                    Divider().overlay(TokenColors.divider.opacity(0.6))
                        .padding(.leading, 28)
                }
            }
        }
    }

    private var groupedList: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(SessionGrouping.grouped(ordered)) { group in
                sourceSection(group.source, group.sessions)
            }
        }
    }

    /// A collapsible source group — a VSCode-git-style header (chevron · SOURCE · count)
    /// over its rows; clicking the header collapses/expands the group.
    private func sourceSection(_ source: SessionSource, _ sessions: [Session]) -> some View {
        let isCollapsed = collapsedSources.contains(source.rawValue)
        return VStack(alignment: .leading, spacing: 0) {
            Button { toggle(source) } label: {
                HStack(spacing: 6) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(TokenColors.midGray)
                        .frame(width: 10, alignment: .center)
                    Text(SessionGrouping.label(for: source).uppercased())
                        .font(TokenFonts.ui(10, weight: .semibold))
                        .foregroundStyle(TokenColors.midGray)
                    Text("\(sessions.count)")
                        .font(TokenFonts.ui(10))
                        .foregroundStyle(TokenColors.midGray.opacity(0.7))
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !isCollapsed {
                ForEach(sessions) { session in
                    SessionRow(session: session,
                               disambiguator: disambiguationLabels[session.id],
                               onJump: onJump)
                }
            }
            Divider().overlay(TokenColors.divider.opacity(0.6))
        }
    }

    private func toggle(_ source: SessionSource) {
        if collapsedSources.contains(source.rawValue) {
            collapsedSources.remove(source.rawValue)
        } else {
            collapsedSources.insert(source.rawValue)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("cPerch")
                .font(TokenFonts.ui(13, weight: .semibold))
            Spacer()
            Text(summaryLabel)
                .font(TokenFonts.ui(11))
                .foregroundStyle(TokenColors.midGray)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var summaryLabel: String {
        let needs = sessions.filter { $0.status == .needsInput }.count
        if needs > 0 { return needs == 1 ? "1 needs you" : "\(needs) need you" }
        let running = sessions.filter { $0.status == .running }.count
        if running > 0 { return running == 1 ? "1 running" : "\(running) running" }
        return "all quiet"
    }

    private var emptyState: some View {
        HStack {
            Spacer()
            Text("No active sessions")
                .font(TokenFonts.ui(12))
                .foregroundStyle(TokenColors.midGray)
            Spacer()
        }
        .padding(.vertical, 24)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button(action: onSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(TokenColors.midGray)
            .help("Settings")

            Spacer()

            Button(action: onQuit) {
                Text("Quit cPerch")
                    .font(TokenFonts.ui(11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(TokenColors.midGray)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

/// One roster row: status dot · project name + preview (and wait label) · Jump.
struct SessionRow: View {
    let session: Session
    /// L2: a muted secondary label (relative time) shown under the name when this row's
    /// `displayName` collides with another visible row; nil when the name is unique.
    var disambiguator: String? = nil
    var onJump: (Session) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            StatusDot(status: session.status)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(session.displayName)
                        .font(TokenFonts.ui(13, weight: .medium))
                        .lineLimit(1)
                    if let disambiguator, !disambiguator.isEmpty {
                        // Muted secondary label disambiguating same-named rows (L2).
                        Text(disambiguator)
                            .font(TokenFonts.ui(10))
                            .foregroundStyle(TokenColors.midGray)
                            .lineLimit(1)
                    }
                    if session.status == .needsInput, let label = blockedLabel {
                        Text(label)
                            .font(TokenFonts.ui(10, weight: .medium))
                            .foregroundStyle(TokenColors.needsInput)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(
                                Capsule().fill(TokenColors.needsInput.opacity(0.14))
                            )
                    }
                }

                if let preview = session.latestMessage, !preview.isEmpty {
                    Text(preview)
                        .font(TokenFonts.mono(11))
                        .foregroundStyle(TokenColors.midGray)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 6)

            Button {
                onJump(session)
            } label: {
                Text("Jump")
                    .font(TokenFonts.ui(11, weight: .medium))
            }
            .buttonStyle(.borderless)
            .help("Focus the existing \(session.displayName) window")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }

    /// "blocked Nm" / "blocked Nh" relative to now, derived from `blockedSince`
    /// (when it entered needsInput), falling back to `lastActivity`.
    private var blockedLabel: String? {
        let since = session.blockedSince ?? session.lastActivity
        return SessionRow.relativeWait(since: since)
    }

    static func relativeWait(since: Date, now: Date = Date()) -> String {
        let seconds = max(0, now.timeIntervalSince(since))
        let minutes = Int(seconds / 60)
        if minutes < 1 { return "blocked now" }
        if minutes < 60 { return "blocked \(minutes)m" }
        let hours = minutes / 60
        let rem = minutes % 60
        return rem == 0 ? "blocked \(hours)h" : "blocked \(hours)h \(rem)m"
    }
}

/// The per-row status dot — Claude accent palette.
struct StatusDot: View {
    let status: DerivedStatus

    private var color: Color {
        switch status {
        case .needsInput: return TokenColors.needsInput   // orange
        case .running:    return TokenColors.running       // blue
        case .concluded:  return TokenColors.concluded     // green
        }
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 9, height: 9)
            .accessibilityLabel(Text(status.rawValue))
    }
}

// MARK: - All-states sample (structural verification of every state)
//
// The frozen StubSessionStore only emits needsInput + running. This sample supplies
// one session of EACH status — including concluded — so the roster's rendering of all
// three states is exercised and type-checked at build time. (Xcode's #Preview macro is
// unavailable under a plain SwiftPM/CLT build, so we expose a sample view instead; the
// app drives the real store. Manual visual verification is deferred to integration.)
extension RosterView {
    /// One session per DerivedStatus — covers needsInput, running, and concluded.
    static var allStatesSample: [Session] {
        let now = Date()
        return [
            Session(id: "sample-needs", projectPath: "/Users/you/Projects/api", displayName: "api",
                    source: .cli, status: .needsInput,
                    latestMessage: "Can I run the database migration against prod?",
                    lastActivity: now, blockedSince: now.addingTimeInterval(-260),
                    pid: 1234, host: .terminal(app: "iTerm2", tty: "ttys004")),
            Session(id: "sample-run", projectPath: "/Users/you/Projects/web", displayName: "web",
                    source: .desktop, status: .running,
                    latestMessage: "Refactoring the router and updating the call sites…",
                    lastActivity: now, blockedSince: nil,
                    pid: 5678, host: .desktop(bundleID: "com.anthropic.claudefordesktop")),
            Session(id: "sample-done", projectPath: "/Users/you/Projects/cli", displayName: "cli",
                    source: .cli, status: .concluded,
                    latestMessage: "All tests passing. Done.",
                    lastActivity: now.addingTimeInterval(-900), blockedSince: nil,
                    pid: nil, host: .terminal(app: "Terminal", tty: "ttys001")),
        ]
    }

    /// A roster bound to `allStatesSample`, for visual spot-checks during integration.
    static func allStatesPreview() -> RosterView {
        RosterView(sessions: allStatesSample, onJump: { _ in }, onQuit: {})
    }

    /// Two same-project rows sharing a `displayName` (plus one unique row) — exercises the
    /// L2 collision label: the two `claude-toolbar-mac` rows should show distinct muted
    /// relative-time secondaries, the `api` row none.
    static var collisionSample: [Session] {
        let now = Date()
        return [
            Session(id: "abcd-1111", projectPath: "/Users/you/Projects/claude-toolbar-mac",
                    displayName: "claude-toolbar-mac", source: .cli, status: .running,
                    latestMessage: "Wiring the disambiguation label into the row…",
                    lastActivity: now.addingTimeInterval(-120), blockedSince: nil,
                    pid: 4242, host: .terminal(app: "iTerm2", tty: "ttys002")),
            Session(id: "efgh-2222", projectPath: "/Users/you/Projects/claude-toolbar-mac",
                    displayName: "claude-toolbar-mac", source: .cli, status: .concluded,
                    latestMessage: "All tests passing. Done.",
                    lastActivity: now.addingTimeInterval(-3600), blockedSince: nil,
                    pid: nil, host: .terminal(app: "Terminal", tty: "ttys003")),
            Session(id: "ijkl-3333", projectPath: "/Users/you/Projects/api", displayName: "api",
                    source: .cli, status: .running,
                    latestMessage: "Running the suite…",
                    lastActivity: now.addingTimeInterval(-30), blockedSince: nil,
                    pid: 7777, host: .terminal(app: "iTerm2", tty: "ttys004")),
        ]
    }

    /// A roster bound to `collisionSample`, for visually verifying the L2 secondary label.
    static func collisionPreview() -> RosterView {
        RosterView(sessions: collisionSample, onJump: { _ in }, onQuit: {})
    }
}
