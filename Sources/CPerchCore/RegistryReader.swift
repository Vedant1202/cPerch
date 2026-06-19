import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// RegistryReader (P1-B) — reads ~/.claude/sessions/<pid>.json → [RegistryEntry].
//
// The registry is Claude's pid → sessionId bridge (SPEC §3). Each file is a small
// JSON object keyed by process id. We decode pid/sessionId/cwd/status/kind/version;
// `status` is OPTIONAL — older Claude (and the desktop app) omit it, so we tolerate
// nil rather than treating its absence as an error.
//
// Pure & Foundation-only (SPEC §6): the sessions directory is injectable so tests
// point at a fixture dir. Reads are resilient — a malformed, non-JSON, or otherwise
// undecodable file is skipped, never aborting the whole scan. Read-only: cPerch
// never writes to ~/.claude (SPEC §8).
// ─────────────────────────────────────────────────────────────────────────────
public struct RegistryReader {

    /// The directory of `<pid>.json` session files to scan.
    public let directory: URL

    /// - Parameter directory: the sessions directory. Defaults to `~/.claude/sessions`.
    public init(directory: URL = RegistryReader.defaultDirectory) {
        self.directory = directory
    }

    /// `~/.claude/sessions` for the current user.
    public static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/sessions", isDirectory: true)
    }

    /// Read every `*.json` file in `directory` into a `RegistryEntry`.
    ///
    /// Order follows the filesystem enumeration and is not guaranteed. A missing
    /// directory yields `[]`; individual files that fail to read or decode are
    /// skipped so one bad file can't sink the rest.
    public func read() -> [RegistryEntry] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: directory.path) else {
            return []   // directory absent / unreadable — nothing to report
        }

        return names.sorted().compactMap { name in
            guard name.hasSuffix(".json") else { return nil }
            let url = directory.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: url) else { return nil }
            return Self.decode(data)
        }
    }

    /// Decode one session file's bytes into a `RegistryEntry`, or `nil` if malformed
    /// or missing a required field.
    private static func decode(_ data: Data) -> RegistryEntry? {
        guard let dto = try? JSONDecoder().decode(SessionFile.self, from: data) else {
            return nil
        }
        return RegistryEntry(
            pid: dto.pid,
            sessionId: dto.sessionId,
            cwd: dto.cwd,
            status: dto.status,      // optional — absent in older/desktop files
            kind: dto.kind,
            version: dto.version,
            startedAt: dto.startedAt.map { Date(timeIntervalSince1970: Double($0) / 1000.0) }
        )                            // `startedAt` is epoch MILLISECONDS; absent → nil (D3)
    }

    /// On-disk shape of a `~/.claude/sessions/<pid>.json` file. Only the fields cPerch
    /// needs are declared; any others (e.g. `entrypoint`, `procStart`) are ignored.
    /// `RegistryEntry` is the frozen public contract and intentionally not `Codable`,
    /// so this private DTO carries the decoding. `startedAt` is the registry's epoch-
    /// MILLISECONDS session-start instant (D3 PID-reuse guard); it is optional because
    /// older CLIs / partial writes may omit it.
    private struct SessionFile: Decodable {
        let pid: Int
        let sessionId: String
        let cwd: String
        let status: String?
        let kind: String?
        let version: String?
        let startedAt: Int?
    }
}
