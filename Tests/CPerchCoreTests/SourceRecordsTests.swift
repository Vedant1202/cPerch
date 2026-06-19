import Testing
import Foundation
@testable import CPerchCore

// swift-testing (`import Testing`) — XCTest isn't in the Command Line Tools.
//
// dedup-hardening Phase 0: the frozen source records (SourceRecords.swift) gain two
// optional, nil-defaulted fields for the D3 PID-reuse guard — ProcessRecord.startTime
// and RegistryEntry.startedAt. These tests pin the ADDITIVE contract:
//   • the pre-Phase-0 initializer call shapes still compile (backward compatible), and
//   • the new fields default to nil and round-trip when supplied.
// See docs/specs/dedup-hardening-v0.1.md (DD-6).
@Suite("SourceRecords — additive contract (startTime / startedAt / aiTitle)")
struct SourceRecordsContractTests {

    private let instant = Date(timeIntervalSince1970: 1_781_750_000)

    @Test("ProcessRecord: legacy init still compiles; startTime defaults to nil")
    func processStartTimeDefaultsNil() {
        let p = ProcessRecord(pid: 1, ppid: 1, tty: nil, cwd: nil, cpu: 0)   // pre-Phase-0 call shape
        #expect(p.startTime == nil)
        #expect(p.resumedFrom == nil)   // B1 additive field also defaults nil
    }

    @Test("ProcessRecord: startTime round-trips when supplied")
    func processStartTimeRoundTrips() {
        let p = ProcessRecord(pid: 1, ppid: 1, tty: nil, cwd: nil, cpu: 0, startTime: instant)
        #expect(p.startTime == instant)
    }

    @Test("RegistryEntry: legacy init still compiles; startedAt defaults to nil")
    func registryStartedAtDefaultsNil() {
        let e = RegistryEntry(pid: 1, sessionId: "s", cwd: "/c",
                              status: nil, kind: nil, version: nil)            // pre-Phase-0 call shape
        #expect(e.startedAt == nil)
        #expect(e.entrypoint == nil)   // v0.3 additive field also defaults nil
    }

    @Test("RegistryEntry: startedAt round-trips when supplied")
    func registryStartedAtRoundTrips() {
        let e = RegistryEntry(pid: 1, sessionId: "s", cwd: "/c",
                              status: nil, kind: nil, version: nil, startedAt: instant)
        #expect(e.startedAt == instant)
    }

    // v0.2 (roster-and-merge-quality) Phase 0: TranscriptSignal gains an optional, nil-defaulted
    // `aiTitle` for L2 (the AI-generated session title). Same additive contract.
    @Test("TranscriptSignal: legacy init still compiles; aiTitle defaults to nil")
    func transcriptAiTitleDefaultsNil() {
        let s = TranscriptSignal(sessionId: "s", cwd: "/c", lastRole: nil, lastStopReason: nil,
                                 pendingToolUses: 0, lastText: nil, lastActivity: instant)  // pre-v0.2 shape
        #expect(s.aiTitle == nil)
    }

    @Test("TranscriptSignal: aiTitle round-trips when supplied")
    func transcriptAiTitleRoundTrips() {
        let s = TranscriptSignal(sessionId: "s", cwd: "/c", lastRole: nil, lastStopReason: nil,
                                 pendingToolUses: 0, lastText: nil, lastActivity: instant,
                                 aiTitle: "My Cool Title")
        #expect(s.aiTitle == "My Cool Title")
    }
}
