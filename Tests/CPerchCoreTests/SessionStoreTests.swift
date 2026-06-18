import Testing
import Foundation
@testable import CPerchCore

// P2 — the pure, deterministic helpers of SessionStore. The store's I/O + timer/FSEvents
// wiring is verified separately via `swift run CPerchApp --print` on a live machine.

@Suite("SessionStore helpers")
struct SessionStoreHelperTests {

    private func session(_ id: String, _ status: DerivedStatus, blockedSince: Date? = nil,
                         lastActivity: Date = Date(), host: HostRef = .unknown) -> Session {
        Session(id: id, projectPath: "/p/\(id)", displayName: id, source: .cli, status: status,
                latestMessage: nil, lastActivity: lastActivity, blockedSince: blockedSince,
                pid: nil, host: host)
    }

    // MARK: blockedSince carry-forward

    @Test func stampsBlockedSinceWhenEnteringNeedsInput() {
        let now = Date()
        let out = SessionStore.applyBlockedSince(
            previous: [session("a", .running)],
            merged: [session("a", .needsInput)], now: now)
        #expect(out[0].blockedSince == now)
    }

    @Test func keepsOriginalBlockedSinceWhileStillNeedsInput() {
        let earlier = Date(timeIntervalSince1970: 1_000_000)
        let now = Date(timeIntervalSince1970: 1_000_300)
        let out = SessionStore.applyBlockedSince(
            previous: [session("a", .needsInput, blockedSince: earlier)],
            merged: [session("a", .needsInput)], now: now)
        #expect(out[0].blockedSince == earlier)   // not reset across refreshes
    }

    @Test func clearsBlockedSinceWhenNoLongerNeedsInput() {
        let out = SessionStore.applyBlockedSince(
            previous: [session("a", .needsInput, blockedSince: Date(timeIntervalSince1970: 1))],
            merged: [session("a", .running)], now: Date())
        #expect(out[0].blockedSince == nil)
    }

    // MARK: concluded retention

    @Test func keepsAllLiveSessions() {
        let now = Date()
        let out = SessionStore.applyRetention(
            [session("a", .running, lastActivity: now), session("b", .needsInput, lastActivity: now)],
            now: now, window: 3 * 3600, cap: 10)
        #expect(out.count == 2)
    }

    @Test func dropsConcludedOlderThanWindow() {
        let now = Date()
        let out = SessionStore.applyRetention(
            [session("a", .running, lastActivity: now),
             session("b", .concluded, lastActivity: now.addingTimeInterval(-4 * 3600))],
            now: now, window: 3 * 3600, cap: 10)
        #expect(out.map(\.id) == ["a"])
    }

    @Test func capsConcludedToMostRecent() {
        let now = Date()
        let concluded = (0..<15).map { i in
            session("c\(i)", .concluded, lastActivity: now.addingTimeInterval(-Double(i)))
        }
        let kept = SessionStore.applyRetention(concluded, now: now, window: 24 * 3600, cap: 10)
        #expect(kept.count == 10)
        #expect(kept.contains { $0.id == "c0" })    // most recent kept
        #expect(!kept.contains { $0.id == "c14" })  // oldest dropped
    }

    // MARK: terminal-app resolution (walk ppid → owning terminal)

    @Test func resolvesITermFromAncestry() {
        let ancestry: [Int: (ppid: Int, name: String)] = [
            100: (90, "claude"), 90: (50, "-zsh"),
            50: (1, "/Applications/iTerm.app/Contents/MacOS/iTerm2")]
        #expect(SessionStore.resolveTerminalApp(forPid: 100, ancestry: ancestry) == "iTerm2")
    }

    @Test func resolvesTerminalThroughLogin() {
        let ancestry: [Int: (ppid: Int, name: String)] = [
            100: (90, "claude"), 90: (80, "-zsh"), 80: (40, "login"),
            40: (1, "/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal")]
        #expect(SessionStore.resolveTerminalApp(forPid: 100, ancestry: ancestry) == "Terminal")
    }

    @Test func defaultsToTerminalWhenUnresolved() {
        let ancestry: [Int: (ppid: Int, name: String)] = [100: (1, "claude")]
        #expect(SessionStore.resolveTerminalApp(forPid: 100, ancestry: ancestry) == "Terminal")
    }
}
