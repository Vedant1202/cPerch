import Foundation
import AppKit
import CPerchCore
import UserNotifications

/// Posts the *calm* cPerch banners (SPEC AC4 · Locked Decision 5 · v0.4 #4).
///
/// Restraint is the whole point: cPerch interrupts you **only** on meaningful
/// transitions — a session crossing *into* `needsInput`, a session that just *hit an
/// API error*, or (opt-in) a session that just *finished*. Never for work that's
/// merely running; by default never for completion; by default never for agents that
/// just appeared. Each kind is gated by its own preference flag. When several
/// needs-input sessions cross at once we coalesce to a single banner so a fan-out of
/// agents can't fan out into a wall of notifications. Focus/DND is left entirely to
/// macOS: we post through the standard `UNUserNotificationCenter` and let the OS
/// decide whether to actually show anything.
///
/// The decision lives in ``banners(previous:current:preferences:notifyNewAgent:)`` —
/// a pure, side-effect-free function so the transition/coalesce rules are verifiable
/// by reading (and by the `#if DEBUG` self-check at the bottom of this file). The
/// posting path (``reconcile(previous:current:notifyNewAgent:preferences:)``) just
/// calls it and hands the result to the notification center.
///
/// `Notifier` is an `NSObject` and the notification center's delegate so it can
/// handle **taps**: each banner carries its session id in `userInfo`, and a tap
/// resolves that id against the last posted snapshot and calls `Jumper.jump(to:)`.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    // `UNUserNotificationCenter.current()` THROWS unless the process is a real bundle (has a
    // CFBundleIdentifier). Resolve it guardedly so a bare `swift run` binary (no Info.plist)
    // never crashes — notifications simply no-op until the app runs as CPerch.app (built by
    // build.sh, which also ad-hoc signs it so the notification center is available).
    private let center: UNUserNotificationCenter?
    private var didRequestAuthorization = false
    /// The most recent snapshot handed to ``reconcile`` — the lookup table a tap uses to
    /// resolve a banner's `sessionId` back to a `Session` for `Jumper.jump(to:)`.
    private var latestSessions: [Session] = []

    override init() {
        self.center = Bundle.main.bundleIdentifier != nil ? .current() : nil
        super.init()
        // Become the delegate so taps route to `userNotificationCenter(_:didReceive:…)`.
        // Guard the no-bundle case: there is no center to delegate for under `swift run`.
        center?.delegate = self
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

    /// One banner to post, with its tap target and kind. The kind distinguishes the
    /// three triggers (so the self-check and any future per-kind styling can tell them
    /// apart); `sessionId` is the tap target (nil for the coalesced needs-input
    /// summary, which has no single session to open).
    struct Banner: Equatable {
        let text: String
        let sessionId: String?
        let kind: Kind
        enum Kind { case needsInput, error, completion }
    }

    /// The banner(s) to post for the change from `previous` to `current`, each kind
    /// gated by its preference flag.
    ///
    /// **needsInput** (only if `preferences.notifyOnNeedsInput`): a session that is
    /// `needsInput` now and was **present before with some other status**. That
    /// "present before" rule is what makes notifications calm: a session flapping
    /// running→needsInput→running fires once per real block, and a session that's
    /// simply *still* blocked across refreshes never re-fires. New sessions are silent
    /// unless `notifyNewAgent`. **Coalesced:** N > 1 → one summary
    /// `"N agents need you"` (no session id); exactly 1 → a named banner with its id.
    ///
    /// **error** (only if `preferences.notifyOnError`): a session whose `hadApiError`
    /// is `true` now and was `false`/absent before — the false→true transition. This
    /// naturally debounces to one banner the moment the API-error record appears, and
    /// never re-fires while it lingers in the tail. New errored sessions are silent
    /// unless `notifyNewAgent`. One banner per such session (NOT coalesced — an errored
    /// agent is specific and you want its name/target).
    ///
    /// **completion** (only if `preferences.notifyOnCompletion`, off by default): a
    /// session `.concluded` now that was **present before with a non-concluded
    /// status** — the →concluded transition. One banner per such session. New sessions
    /// (already concluded on first sight) are silent.
    ///
    /// Pure and side-effect-free: depends only on its inputs, touches no globals,
    /// posts nothing.
    static func banners(previous: [Session],
                        current: [Session],
                        preferences: Preferences,
                        notifyNewAgent: Bool = false) -> [Banner] {
        let previousById = Dictionary(
            previous.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var result: [Banner] = []

        // ── needsInput (coalesced) ──────────────────────────────────────────────
        if preferences.notifyOnNeedsInput {
            let transitioned = current.filter { session in
                guard session.status == .needsInput else { return false }  // only →needsInput
                if let prior = previousById[session.id] {
                    return prior.status != .needsInput   // present before, but not already blocked
                }
                return notifyNewAgent                     // brand-new session: silent unless opted in
            }
            switch transitioned.count {
            case 0:
                break
            case 1:
                result.append(Banner(text: "\(transitioned[0].displayName) needs your input",
                                     sessionId: transitioned[0].id, kind: .needsInput))
            default:
                result.append(Banner(text: "\(transitioned.count) agents need you",
                                     sessionId: nil, kind: .needsInput))
            }
        }

        // ── error (one per false→true transition) ───────────────────────────────
        if preferences.notifyOnError {
            for session in current where session.hadApiError {
                if let prior = previousById[session.id] {
                    guard !prior.hadApiError else { continue }   // already errored → no re-fire
                } else if !notifyNewAgent {
                    continue                                     // brand-new errored session: silent
                }
                result.append(Banner(text: "\(session.displayName) hit an error",
                                     sessionId: session.id, kind: .error))
            }
        }

        // ── completion (one per →concluded transition) ──────────────────────────
        if preferences.notifyOnCompletion {
            for session in current where session.status == .concluded {
                // Only on the transition: present before with a non-concluded status.
                // A brand-new (already-concluded) session never fires — there was no
                // active work to "complete" from cPerch's vantage.
                guard let prior = previousById[session.id], prior.status != .concluded else { continue }
                result.append(Banner(text: "\(session.displayName) finished",
                                     sessionId: session.id, kind: .completion))
            }
        }

        return result
    }

    // MARK: - Posting (side-effecting)

    /// Reconcile two session snapshots and post a banner for each ``Banner`` returned
    /// by ``banners(previous:current:preferences:notifyNewAgent:)``. Authorization is
    /// requested lazily on first use. Suppression under Focus/DND is the OS's job — we
    /// always `add`; macOS decides whether to surface it.
    ///
    /// The signature is FROZEN: `MenuBarController` calls
    /// `reconcile(previous:current:preferences:)`, relying on the defaulted
    /// `notifyNewAgent`. Do not reorder/rename these parameters.
    func reconcile(previous: [Session],
                   current: [Session],
                   notifyNewAgent: Bool = false,
                   preferences: Preferences = .defaults) {
        // Remember the current snapshot so a tap can resolve its banner's session id —
        // even for kinds we don't post this cycle (the lookup must stay fresh).
        latestSessions = current
        let banners = Self.banners(previous: previous, current: current,
                                   preferences: preferences, notifyNewAgent: notifyNewAgent)
        guard !banners.isEmpty, let center else { return }   // no bundle → notifications no-op
        Task { await post(banners, center: center, preferences: preferences) }
    }

    /// Ensure authorization (once), then post each banner. Failures are swallowed:
    /// a denied permission or a post error must never disrupt the user's sessions.
    private func post(_ banners: [Banner], center: UNUserNotificationCenter,
                      preferences: Preferences) async {
        await requestAuthorizationIfNeeded(center: center)
        for banner in banners {
            let content = UNMutableNotificationContent()
            content.title = "cPerch"
            content.body = banner.text
            // Tap target: stash the session id so the delegate can resolve + jump.
            if let sessionId = banner.sessionId {
                content.userInfo["sessionId"] = sessionId
            }
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

    // MARK: - Tap-to-open (UNUserNotificationCenterDelegate)

    /// A tap on a delivered banner: resolve its `userInfo["sessionId"]` against the
    /// last snapshot and focus that session's host (terminal tab / Claude app) via
    /// `Jumper`. Jumper's AppleScript/NSWorkspace work must run on the main thread.
    /// Always call the completion handler so the system can retire the response.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        if let sessionId = info["sessionId"] as? String,
           let session = latestSessions.first(where: { $0.id == sessionId }) {
            if Thread.isMainThread {
                Jumper.jump(to: session)
            } else {
                DispatchQueue.main.async { Jumper.jump(to: session) }
            }
        }
        completionHandler()
    }
}

// MARK: - Self-check (executable spec for the pure decision)

#if DEBUG
/// Demonstrates the AC4 transition/coalesce rules + the v0.4 #4 error/completion
/// kinds. Run once at startup (see main.swift) so a regression in the pure logic
/// trips immediately. This stands in for a unit test: CPerchApp has no test target,
/// but the decision is a pure function, so a `precondition` is a sound self-verify.
func cperchNotifierSelfCheck() {
    let now = Date()
    func session(_ id: String, _ status: DerivedStatus, hadApiError: Bool = false) -> Session {
        Session(id: id, projectPath: "/p/\(id)", displayName: id, source: .cli,
                status: status, latestMessage: nil, lastActivity: now,
                blockedSince: status == .needsInput ? now : nil, pid: nil, host: .unknown,
                hadApiError: hadApiError)
    }

    // A preferences copy with one kind toggled, for the gating checks.
    var noNeedsInput = Preferences.defaults; noNeedsInput.notifyOnNeedsInput = false
    var noError = Preferences.defaults;      noError.notifyOnError = false
    var withCompletion = Preferences.defaults; withCompletion.notifyOnCompletion = true
    // Sanity on the defaults the gating relies on (error on, completion off).
    precondition(Preferences.defaults.notifyOnNeedsInput, "needsInput expected on by default")
    precondition(Preferences.defaults.notifyOnError, "error expected on by default")
    precondition(!Preferences.defaults.notifyOnCompletion, "completion expected off by default")

    // 1) One running → needsInput transition yields exactly 1 needsInput banner (named, with id).
    let one = Notifier.banners(previous: [session("a", .running)],
                               current: [session("a", .needsInput)],
                               preferences: .defaults)
    precondition(one.count == 1 && one[0].kind == .needsInput && one[0].sessionId == "a",
                 "expected 1 named needsInput banner for a single →needsInput transition")

    // 2) Three simultaneous transitions coalesce into 1 summary banner (no session id).
    let many = Notifier.banners(
        previous: [session("a", .running), session("b", .running), session("c", .running)],
        current:  [session("a", .needsInput), session("b", .needsInput), session("c", .needsInput)],
        preferences: .defaults)
    precondition(many == [Notifier.Banner(text: "3 agents need you", sessionId: nil, kind: .needsInput)],
                 "expected 1 coalesced needsInput banner for 3 transitions")

    // 3) A running → running change yields no banner.
    precondition(Notifier.banners(previous: [session("a", .running)],
                                  current: [session("a", .running)],
                                  preferences: .defaults).isEmpty,
                 "expected no banner when status does not enter needsInput")

    // 4) A session still blocked across refreshes does NOT re-fire (calm).
    precondition(Notifier.banners(previous: [session("a", .needsInput)],
                                  current: [session("a", .needsInput)],
                                  preferences: .defaults).isEmpty,
                 "expected no banner for a still-blocked session")

    // 5) A brand-new already-blocked agent is silent by default, opt-in via flag.
    precondition(Notifier.banners(previous: [], current: [session("new", .needsInput)],
                                  preferences: .defaults).isEmpty,
                 "expected new-agent needsInput to be silent by default")
    precondition(Notifier.banners(previous: [], current: [session("new", .needsInput)],
                                  preferences: .defaults, notifyNewAgent: true).count == 1,
                 "expected new-agent needsInput to notify when notifyNewAgent is true")

    // 6) Entering concluded never fires a needsInput banner; with completion OFF (default),
    //    a →concluded transition produces no banner at all.
    precondition(Notifier.banners(previous: [session("a", .running)],
                                  current: [session("a", .concluded)],
                                  preferences: .defaults).isEmpty,
                 "expected no banner when a session concludes (completion off by default)")

    // 7) needsInput gated off: the same →needsInput transition yields nothing.
    precondition(Notifier.banners(previous: [session("a", .running)],
                                  current: [session("a", .needsInput)],
                                  preferences: noNeedsInput).isEmpty,
                 "expected no needsInput banner when notifyOnNeedsInput is false")

    // 8) Error: a false→true hadApiError transition fires exactly one .error banner (named, with id).
    let err = Notifier.banners(previous: [session("a", .running, hadApiError: false)],
                               current: [session("a", .running, hadApiError: true)],
                               preferences: .defaults)
    precondition(err.count == 1 && err[0].kind == .error && err[0].sessionId == "a",
                 "expected 1 .error banner for a false→true hadApiError transition")

    // 9) Error debounces: still-errored across refreshes does NOT re-fire.
    precondition(Notifier.banners(previous: [session("a", .running, hadApiError: true)],
                                  current: [session("a", .running, hadApiError: true)],
                                  preferences: .defaults).isEmpty,
                 "expected no .error banner while an error lingers (debounced on transition)")

    // 10) Error gated off: the same error transition yields nothing.
    precondition(Notifier.banners(previous: [session("a", .running, hadApiError: false)],
                                  current: [session("a", .running, hadApiError: true)],
                                  preferences: noError).isEmpty,
                 "expected no .error banner when notifyOnError is false")

    // 11) Completion: with it enabled, a →concluded transition fires exactly one .completion banner.
    let done = Notifier.banners(previous: [session("a", .running)],
                                current: [session("a", .concluded)],
                                preferences: withCompletion)
    precondition(done.count == 1 && done[0].kind == .completion && done[0].sessionId == "a",
                 "expected 1 .completion banner for a →concluded transition when enabled")

    // 12) Completion does NOT fire for a brand-new (already-concluded) session, even when enabled.
    precondition(Notifier.banners(previous: [], current: [session("new", .concluded)],
                                  preferences: withCompletion).isEmpty,
                 "expected no .completion banner for a brand-new already-concluded session")
}
#endif
