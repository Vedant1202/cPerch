import Testing
import Foundation
@testable import CPerchCore

// The VoiceOver string builders (v0.5 A4) are pure, so the spoken output is pinned here.
// `accessibilityLabel(for:)` composes a row's announcement; `menuBarAccessibilityValue(...)`
// the bar item's live value.

@Suite("AccessibilityText — VoiceOver label / value")
struct AccessibilityTextTests {

    private func session(_ status: DerivedStatus, name: String = "api", preview: String? = nil,
                         blockedSince: Date? = nil, lastActivity: Date) -> Session {
        Session(id: "x", projectPath: "/p/\(name)", displayName: name, source: .cli,
                status: status, latestMessage: preview, lastActivity: lastActivity,
                blockedSince: blockedSince, pid: 1, host: .unknown)
    }

    @Test("needs-input: name, status, blocked wait, and preview")
    func needsInputLabel() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let s = session(.needsInput, name: "api", preview: "Can I run the migration?",
                        blockedSince: now.addingTimeInterval(-260), lastActivity: now)
        #expect(accessibilityLabel(for: s, now: now)
                == "api, needs input, blocked 4 minutes. Latest: Can I run the migration?")
    }

    @Test("running: name, status, preview — no blocked clause")
    func runningLabel() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let s = session(.running, name: "web", preview: "Refactoring the router", lastActivity: now)
        #expect(accessibilityLabel(for: s, now: now) == "web, running. Latest: Refactoring the router")
    }

    @Test("concluded with no preview: just name and status")
    func concludedLabel() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let s = session(.concluded, name: "cli", preview: nil, lastActivity: now)
        #expect(accessibilityLabel(for: s, now: now) == "cli, concluded")
    }

    @Test("blocked wait uses a singular minute")
    func singularMinute() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let s = session(.needsInput, name: "api", blockedSince: now.addingTimeInterval(-60), lastActivity: now)
        #expect(accessibilityLabel(for: s, now: now) == "api, needs input, blocked 1 minute")
    }

    @Test("menu-bar value: needs-you / running / quiet, singular vs plural")
    func menuValue() {
        #expect(menuBarAccessibilityValue(aggregate: .needsInput, needsInputCount: 2, runningCount: 1)
                == "2 sessions need you")
        #expect(menuBarAccessibilityValue(aggregate: .needsInput, needsInputCount: 1, runningCount: 0)
                == "1 session needs you")
        #expect(menuBarAccessibilityValue(aggregate: .running, needsInputCount: 0, runningCount: 3) == "3 running")
        #expect(menuBarAccessibilityValue(aggregate: .running, needsInputCount: 0, runningCount: 1) == "1 running")
        #expect(menuBarAccessibilityValue(aggregate: .idle, needsInputCount: 0, runningCount: 0) == "all quiet")
    }
}
