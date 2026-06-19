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
    /// The cross-track seam (v0.5): a11y preferences threaded in from MenuBarController.
    /// Defaulted so the existing labeled call sites (and the previews) compile unchanged;
    /// the resolved a11y state is derived from this + the SwiftUI `@Environment` values below.
    var preferences: Preferences = .defaults

    /// Collapsed source-group headers (by `SessionSource.rawValue`) for the grouped view.
    /// `@State` so it survives roster refreshes (SwiftUI preserves it across rootView updates).
    @State private var collapsedSources: Set<String> = []

    // MARK: - Accessibility environment (v0.5)
    //
    // SwiftUI re-invokes `body` automatically when these change, so the roster reacts live to
    // the System Settings ▸ Accessibility ▸ Display toggles. They are the *readable* display
    // preferences — not the Accessibility (AX) control permission cPerch is forbidden to request.

    /// macOS Increase Contrast, as seen by SwiftUI (the "system" input for `highContrast`).
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    /// The active appearance — selects the light vs dark high-contrast accent variant.
    @Environment(\.colorScheme) private var colorScheme
    /// macOS Reduce Transparency, as seen by SwiftUI (the "system" input for `reduceTransparency`).
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// High contrast is effective when the pref forces it, or it's `.system` and macOS has Increase
    /// Contrast on. Computed once here and threaded down (the leaf `StatusDot` never reads prefs/env).
    private var highContrast: Bool {
        effective(preferences.highContrast, system: colorSchemeContrast == .increased)
    }
    /// Dark appearance — picks the dark HC accent set in `Tokens.statusColor`.
    private var isDark: Bool { colorScheme == .dark }
    /// Render a glyph per status (A1) vs the plain colored dot — the user's opt-out.
    private var showShapes: Bool { preferences.showStatusShapes }
    /// Reduce-transparency is effective → draw the roster background solid (A6).
    private var reduceTransparencyEffective: Bool {
        effective(preferences.reduceTransparency, system: reduceTransparency)
    }
    /// The shared color/line for dividers and pill borders. Semantic `separatorColor` already meets
    /// system contrast and boosts under Increase Contrast (A2); in high contrast we also drop the
    /// faint per-row opacity so the lines read at full strength (A3).
    private var dividerColor: Color { TokenColors.separator }

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
            Divider().overlay(dividerColor)

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

            Divider().overlay(dividerColor)
            footer
        }
        .frame(width: 340)
        .background(rosterBackground)
    }

    /// The roster surface (A6): a solid window background when Reduce Transparency is effective,
    /// otherwise the default material so the popover keeps its translucent Claude look.
    @ViewBuilder private var rosterBackground: some View {
        if reduceTransparencyEffective {
            Color(NSColor.windowBackgroundColor)
        } else {
            Color.clear.background(.background)
        }
    }

    // MARK: - List layouts (flat vs grouped-by-source)

    private var flatList: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(ordered.enumerated()), id: \.element.id) { index, session in
                SessionRow(session: session,
                           disambiguator: disambiguationLabels[session.id],
                           showShapes: showShapes, highContrast: highContrast, dark: isDark,
                           onJump: onJump)
                if index < ordered.count - 1 {
                    // Subtle hairline normally; full-strength separator in high contrast (A2/A3).
                    Divider().overlay(dividerColor.opacity(highContrast ? 1 : 0.6))
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
                        .foregroundStyle(TokenColors.secondaryText)
                        .frame(width: 10, alignment: .center)
                    Text(SessionGrouping.label(for: source).uppercased())
                        .font(TokenFonts.ui(10, weight: .semibold))
                        .foregroundStyle(TokenColors.secondaryText)
                    Text("\(sessions.count)")
                        .font(TokenFonts.ui(10))
                        .foregroundStyle(TokenColors.secondaryText)   // semantic; drop the extra opacity (A2)
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
                               showShapes: showShapes, highContrast: highContrast, dark: isDark,
                               onJump: onJump)
                }
            }
            Divider().overlay(dividerColor.opacity(highContrast ? 1 : 0.6))
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
                .foregroundStyle(TokenColors.secondaryText)
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
                .foregroundStyle(TokenColors.secondaryText)
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
            .foregroundStyle(TokenColors.secondaryText)
            .help("Settings")

            Spacer()

            Button(action: onQuit) {
                Text("Quit cPerch")
                    .font(TokenFonts.ui(11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(TokenColors.secondaryText)
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
    /// Resolved a11y state, computed once in `RosterView` and threaded down (A1/A3) so the
    /// leaf views never read prefs/environment themselves.
    var showShapes: Bool = true
    var highContrast: Bool = false
    var dark: Bool = false
    var onJump: (Session) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            StatusDot(status: session.status,
                      showShapes: showShapes, highContrast: highContrast, dark: dark)
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
                            .foregroundStyle(TokenColors.tertiaryText)
                            .lineLimit(1)
                    }
                    if session.status == .needsInput, let label = blockedLabel {
                        // "blocked Nm" pill (A2/A3): readable semantic text on a solid surface with a
                        // status-colored border — was orange text on a 14%-orange fill (≈3:1, illegible).
                        // The hue persists only in the border; the border goes full-strength in HC.
                        let pillStroke = Color(Tokens.statusColor(.needsInput, highContrast: highContrast, dark: dark))
                        Text(label)
                            .font(TokenFonts.ui(10, weight: .medium))
                            .foregroundStyle(TokenColors.secondaryText)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(
                                Capsule().fill(Color(NSColor.windowBackgroundColor))
                            )
                            .overlay(
                                Capsule().strokeBorder(pillStroke.opacity(highContrast ? 1 : 0.7),
                                                       lineWidth: 1)
                            )
                    }
                }

                if let preview = session.latestMessage, !preview.isEmpty {
                    Text(preview)
                        .font(TokenFonts.mono(11))
                        .foregroundStyle(TokenColors.secondaryText)
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
            .accessibilityLabel("Jump")
            .help("Focus the existing \(session.displayName) window")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        // A4: one VoiceOver element per row — the composed spoken state (name, status, wait, latest),
        // with Jump reachable as a named action. The visible Jump button stays functional + labeled.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(CPerchCore.accessibilityLabel(for: session, now: Date()))
        .accessibilityAction(named: "Jump") { onJump(session) }
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

/// The per-row status indicator — a shape-coded SF Symbol (A1) tinted by the high-contrast-aware
/// accent (A2/A3), or the plain colored dot when the user opts shapes off. Color/symbol/contrast are
/// all resolved upstream in `RosterView` and threaded in; this leaf reads no prefs/environment.
struct StatusDot: View {
    let status: DerivedStatus
    /// Render the distinct glyph (default) vs the bare colored dot (the shapes opt-out).
    var showShapes: Bool = true
    var highContrast: Bool = false
    var dark: Bool = false

    /// The accent fill — standard brand hue, or the verified high-contrast variant for the appearance.
    private var color: Color {
        Color(Tokens.statusColor(status, highContrast: highContrast, dark: dark))
    }

    var body: some View {
        Group {
            if showShapes {
                // Distinct silhouette per status (triangle / half-disc / check) so the three states
                // separate in grayscale / for CVD users — the WCAG 1.4.1 fix. ~11 pt reads at the row.
                Image(systemName: Tokens.symbolName(for: statusSymbol(for: status)))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 13, height: 13)
            } else {
                Circle()
                    .fill(color)
                    .frame(width: 9, height: 9)
            }
        }
        // A4: the dot is decorative — the row's combined element speaks the status in words.
        .accessibilityHidden(true)
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
