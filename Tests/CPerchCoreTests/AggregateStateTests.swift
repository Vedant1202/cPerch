import Testing
import Foundation
@testable import CPerchCore

// Uses swift-testing (`import Testing`), not XCTest — XCTest ships only with full
// Xcode, while Testing.framework is in the Command Line Tools. Keeps us Xcode-free.

@Suite("Aggregate dot contract")
struct AggregateStateTests {

    private func session(_ status: DerivedStatus) -> Session {
        Session(id: UUID().uuidString, projectPath: "/x", displayName: "x", source: .cli,
                status: status, latestMessage: nil, lastActivity: Date(), blockedSince: nil,
                pid: nil, host: .unknown)
    }

    @Test func needsInputWins() {
        #expect(AggregateState(sessions: [session(.running), session(.needsInput), session(.concluded)]) == .needsInput)
    }

    @Test func runningWhenNoNeedsInput() {
        #expect(AggregateState(sessions: [session(.running), session(.concluded)]) == .running)
    }

    @Test func idleWhenNoneLive() {
        #expect(AggregateState(sessions: [session(.concluded)]) == .idle)
        #expect(AggregateState(sessions: []) == .idle)
    }

    @Test func stubStoreMatchesContract() {
        let store = StubSessionStore()
        #expect(store.sessions.count == 2)
        #expect(store.aggregate == .needsInput)
    }
}
