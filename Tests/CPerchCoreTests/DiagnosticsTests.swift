import Testing
@testable import CPerchCore

// `diagnosticsText` builds the small, identifier-free string the Help view copies for bug
// reports (v0.6). Pure, so the exact shape is pinned here: two lines, only the inputs.

@Suite("Diagnostics — issue-report text")
struct DiagnosticsTests {

    @Test("two lines: cPerch <version> then macOS <os>")
    func format() {
        #expect(diagnosticsText(appVersion: "0.5.0", osVersion: "14.5 (23F79)")
                == "cPerch 0.5.0\nmacOS 14.5 (23F79)")
    }

    @Test("uses the values verbatim — no identifiers added")
    func verbatim() {
        let s = diagnosticsText(appVersion: "9.9.9", osVersion: "26.0")
        #expect(s == "cPerch 9.9.9\nmacOS 26.0")
        #expect(s.split(separator: "\n").count == 2)
    }
}
