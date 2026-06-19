import Testing
import Foundation
@testable import CPerchCore

@Suite("SessionGrouping — group by source")
struct SessionGroupingTests {

    private func s(_ id: String, _ source: SessionSource) -> Session {
        Session(id: id, projectPath: "/p/\(id)", displayName: id, source: source,
                status: .concluded, latestMessage: nil, lastActivity: Date(timeIntervalSince1970: 1),
                blockedSince: nil, pid: nil, host: .unknown)
    }

    @Test("groups by source in the fixed order; empty groups omitted; within-group order kept")
    func groupsInOrder() {
        let groups = SessionGrouping.grouped([
            s("d1", .desktop), s("c1", .cli), s("c2", .cli), s("u1", .unknown),
        ])
        #expect(groups.map(\.source) == [.cli, .desktop, .unknown])   // .background omitted (none present)
        #expect(groups.first?.sessions.map(\.id) == ["c1", "c2"])     // incoming order preserved
        #expect(groups.last?.sessions.map(\.id) == ["u1"])
    }

    @Test("empty input → no groups")
    func empty() {
        #expect(SessionGrouping.grouped([]).isEmpty)
    }

    @Test("source labels")
    func labels() {
        #expect(SessionGrouping.label(for: .cli) == "CLI")
        #expect(SessionGrouping.label(for: .desktop) == "Desktop")
        #expect(SessionGrouping.label(for: .background) == "Background")
        #expect(SessionGrouping.label(for: .unknown) == "Other")
    }
}
