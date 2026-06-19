import Foundation
import CPerchCore
import UserNotifications

/// Posts the *calm* needs-input banners (SPEC AC4 · Locked Decision 5).
///
/// Restraint is the whole point: cPerch interrupts you **only** when a session
/// crosses *into* `needsInput` — never for work that's merely running, never for
/// sessions that just concluded, and (by default) never for agents that just
/// appeared. When several cross at once we coalesce to a single banner so a fan-out
/// of agents can't fan out into a wall of notifications. Focus/DND is left entirely
/// to macOS: we post through the standard `UNUserNotificationCenter` and let the OS
/// decide whether to actually show anything.
///
/// The decision lives in ``banners(previous:current:notifyNewAgent:)`` — a pure,
/// side-effect-free function so the transition/coalesce rules are verifiable by
/// reading (and by the `#if DEBUG` self-check at the bottom of this file). The
/// posting path (``reconcile(previous:current:notifyNewAgent:)``) just calls it and
/// hands the result to the notification center.
final class Notifier {
    // `UNUserNotificationCenter.current()` THROWS unless the process is a real bundle (has a
    // CFBundleIdentifier). Resolve it guardedly so a bare `swift run` binary (no Info.plist)
    // never crashes — notifications simply no-op until the app runs as CPerch.app (built by
    // build.sh, which also ad-hoc signs it so the notification center is available).
    private let center: UNUserNotificationCenter?
    private var didRequestAuthorization = false

    init() {
        self.center = Bundle.main.bundleIdentifier != nil ? .current() : nil
        #if DEBUG
        Self.runSelfCheckOnce
        #endif
    }

    #if DEBUG
    /// Runs the pure-decision self-check exactly once, the first time any `Notifier`
    /// is created. `main.swift` is frozen for this track, so we self-trigger here
    /// rather than from the app entry point — a regression in the transition/coalesce
    /// logic then trips a `precondition` on first use in any DEBUG build.
    private static let runSelfCheckOnce: Void = { cperchNotifierSelfCheck() }()
    #endif

    // MARK: - Decision (pure)

    /// The banner text(s) to post for the change from `previous` to `current`.
    ///
    /// A *transition into needsInput* is a session that is `needsInput` now and was
    /// **present before with some other status** (running/concluded). That "present
    /// before" rule is what makes notifications calm: a session flapping
    /// running→needsInput→running fires once per real block, and a session that's
    /// simply *still* blocked across refreshes never re-fires.
    ///
    /// - Newly-appeared sessions (an id in `current` absent from `previous`) are
    ///   **silent by default** — even if they show up already blocked. Pass
    ///   `notifyNewAgent: true` to treat a new, already-`needsInput` session as a
    ///   transition too.
    /// - Entering `running` or `concluded` never produces a banner.
    /// - **Coalesce:** 0 transitions → `[]`; exactly 1 → a single named banner;
    ///   N > 1 → one summary banner (`"N agents need you"`), never N banners.
    ///
    /// Pure and side-effect-free: depends only on its inputs, touches no globals,
    /// posts nothing.
    static func banners(previous: [Session],
                        current: [Session],
                        notifyNewAgent: Bool = false) -> [String] {
        let previousStatus = Dictionary(
            previous.map { ($0.id, $0.status) },
            uniquingKeysWith: { first, _ in first }
        )

        let transitioned = current.filter { session in
            guard session.status == .needsInput else { return false }  // only →needsInput
            if let prior = previousStatus[session.id] {
                return prior != .needsInput   // was present before, but not already blocked
            }
            return notifyNewAgent             // brand-new session: silent unless opted in
        }

        switch transitioned.count {
        case 0:
            return []
        case 1:
            return ["\(transitioned[0].displayName) needs your input"]
        default:
            return ["\(transitioned.count) agents need you"]
        }
    }

    // MARK: - Posting (side-effecting)

    /// Reconcile two session snapshots and post a banner for each string returned by
    /// ``banners(previous:current:notifyNewAgent:)`` (at most one, given coalescing).
    /// Authorization is requested lazily on first use. Suppression under Focus/DND is
    /// the OS's job — we always `add`; macOS decides whether to surface it.
    func reconcile(previous: [Session],
                   current: [Session],
                   notifyNewAgent: Bool = false,
                   preferences: Preferences = .defaults) {
        let texts = Self.banners(previous: previous, current: current,
                                 notifyNewAgent: notifyNewAgent)
        guard !texts.isEmpty, let center else { return }   // no bundle → notifications no-op
        Task { await post(texts, center: center, preferences: preferences) }
    }

    /// Ensure authorization (once), then post each banner. Failures are swallowed:
    /// a denied permission or a post error must never disrupt the user's sessions.
    private func post(_ texts: [String], center: UNUserNotificationCenter,
                      preferences: Preferences) async {
        await requestAuthorizationIfNeeded(center: center)
        for text in texts {
            let content = UNMutableNotificationContent()
            content.title = "cPerch"
            content.body = text
            // DND mode: silent → no sound; notify-anyway → time-sensitive (best-effort
            // Focus bypass — truly overriding DND needs the time-sensitive entitlement);
            // system → default sound + level, letting macOS decide.
            switch preferences.dndMode {
            case .system:
                content.sound = .default
            case .notifyAnyway:
                content.sound = .default
                content.interruptionLevel = .timeSensitive
            case .silentAlways:
                content.sound = nil
            }
            // nil trigger → deliver immediately.
            let id = UUID().uuidString
            let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
            try? await center.add(request)

            // Notification life: "timed" clears the delivered notification from Notification
            // Center after N seconds; "persisted" leaves it until the user dismisses it. (macOS
            // controls the on-screen banner duration itself; this governs the lingering copy.)
            if preferences.notificationDismiss == .timed {
                let seconds = preferences.notificationTimeoutSeconds
                Task {
                    try? await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
                    center.removeDeliveredNotifications(withIdentifiers: [id])
                }
            }
        }
    }

    /// Request alert+sound authorization the first time we need to post. Idempotent;
    /// the system only actually prompts the user once.
    private func requestAuthorizationIfNeeded(center: UNUserNotificationCenter) async {
        guard !didRequestAuthorization else { return }
        didRequestAuthorization = true
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }
}

// MARK: - Self-check (executable spec for the pure decision)

#if DEBUG
/// Demonstrates the AC4 transition/coalesce rules. Run once at startup
/// (see main.swift) so a regression in the pure logic trips immediately.
/// This stands in for a unit test: CPerchApp has no test target, but the
/// decision is a pure function, so a `precondition` is a sound self-verify.
func cperchNotifierSelfCheck() {
    let now = Date()
    func session(_ id: String, _ status: DerivedStatus) -> Session {
        Session(id: id, projectPath: "/p/\(id)", displayName: id, source: .cli,
                status: status, latestMessage: nil, lastActivity: now,
                blockedSince: status == .needsInput ? now : nil, pid: nil, host: .unknown)
    }

    // 1) One running → needsInput transition yields exactly 1 banner.
    let one = Notifier.banners(previous: [session("a", .running)],
                               current: [session("a", .needsInput)])
    precondition(one.count == 1, "expected 1 banner for a single →needsInput transition")

    // 2) Three simultaneous transitions coalesce into 1 summary banner.
    let many = Notifier.banners(
        previous: [session("a", .running), session("b", .running), session("c", .running)],
        current:  [session("a", .needsInput), session("b", .needsInput), session("c", .needsInput)])
    precondition(many == ["3 agents need you"], "expected 1 coalesced banner for 3 transitions")

    // 3) A running → running change yields no banner.
    let none = Notifier.banners(previous: [session("a", .running)],
                                current: [session("a", .running)])
    precondition(none.isEmpty, "expected no banner when status does not enter needsInput")

    // 4) A session still blocked across refreshes does NOT re-fire (calm).
    let stillBlocked = Notifier.banners(previous: [session("a", .needsInput)],
                                        current: [session("a", .needsInput)])
    precondition(stillBlocked.isEmpty, "expected no banner for a still-blocked session")

    // 5) A brand-new already-blocked agent is silent by default, opt-in via flag.
    precondition(Notifier.banners(previous: [], current: [session("new", .needsInput)]).isEmpty,
                 "expected new-agent needsInput to be silent by default")
    precondition(Notifier.banners(previous: [], current: [session("new", .needsInput)],
                                  notifyNewAgent: true).count == 1,
                 "expected new-agent needsInput to notify when notifyNewAgent is true")

    // 6) Entering concluded never notifies.
    precondition(Notifier.banners(previous: [session("a", .running)],
                                  current: [session("a", .concluded)]).isEmpty,
                 "expected no banner when a session concludes")
}
#endif
