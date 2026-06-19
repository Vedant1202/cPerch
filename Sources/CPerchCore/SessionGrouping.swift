import Foundation

// cPerch — group the roster by session source (Settings → View → "Group by source").
// Pure + Foundation-only (like RosterDisambiguation): the SwiftUI roster renders these
// groups as collapsible sections; the grouping itself is unit-tested here.

public enum SessionGrouping {

    /// A fixed, stable source order so the grouped roster never reshuffles: CLI first
    /// (the common case), then Desktop, Background, Other.
    static let order: [SessionSource] = [.cli, .desktop, .background, .unknown]

    /// One source's sessions — a stable, `Identifiable` group for SwiftUI's `ForEach`.
    public struct SourceGroup: Identifiable, Equatable, Sendable {
        public let source: SessionSource
        public let sessions: [Session]
        public var id: SessionSource { source }
        public init(source: SessionSource, sessions: [Session]) {
            self.source = source
            self.sessions = sessions
        }
    }

    /// Group `sessions` by `source`, preserving each session's incoming order within its
    /// group and returning the groups in the fixed `order` above. Empty groups are omitted,
    /// so callers can render exactly the sources that are present.
    public static func grouped(_ sessions: [Session]) -> [SourceGroup] {
        var bySource: [SessionSource: [Session]] = [:]
        for s in sessions { bySource[s.source, default: []].append(s) }
        return order.compactMap { src in
            guard let group = bySource[src], !group.isEmpty else { return nil }
            return SourceGroup(source: src, sessions: group)
        }
    }

    /// A human label for a source-group header.
    public static func label(for source: SessionSource) -> String {
        switch source {
        case .cli:        return "Terminal"
        case .desktop:    return "Claude App"
        case .background: return "Background"
        case .unknown:    return "Other"
        }
    }
}
