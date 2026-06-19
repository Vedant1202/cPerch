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
@Suite("SourceRecords — additive contract (startTime / startedAt)")
struct SourceRecordsContractTests {

    private let instant = Date(timeIntervalSince1970: 1_781_750_000)

    @Test("ProcessRecord: legacy init still compiles; startTime defaults to nil")
    func processStartTimeDefaultsNil() {
        let p = ProcessRecord(pid: 1, ppid: 1, tty: nil, cwd: nil, cpu: 0)   // pre-Phase-0 call shape
        #expect(p.startTime == nil)
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
    }

    @Test("RegistryEntry: startedAt round-trips when supplied")
    func registryStartedAtRoundTrips() {
        let e = RegistryEntry(pid: 1, sessionId: "s", cwd: "/c",
                              status: nil, kind: nil, version: nil, startedAt: instant)
        #expect(e.startedAt == instant)
    }
}
