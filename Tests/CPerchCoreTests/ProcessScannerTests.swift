import Testing
import Foundation
@testable import CPerchCore

// swift-testing (`import Testing`) — XCTest isn't in the Command Line Tools.
//
// These tests feed fixture `ps -Ao pid,ppid,tty,%cpu,command` output strings through
// ProcessScanner's injectable process source, so no live machine is required. The
// fixtures are lightly trimmed captures of real `ps` lines (genuine `claude` sessions
// + Claude-desktop Electron helpers + bg/daemon noise) — see Tests/fixtures/.

@Suite("ProcessScanner — parse & filter")
struct ProcessScannerTests {

    // A representative `ps` table: one CLI `claude` with a tty, one claude-code binary
    // launched by the desktop `disclaimer` wrapper (no tty), and a pile of noise that
    // must be filtered out (Electron main, helpers, crashpad, Squirrel/ShipIt, the
    // `claude daemon`, and its --bg-pty-host / --bg-spare workers, plus Claude Usage).
    private let psFixture = """
      PID  PPID TTY         %CPU COMMAND
     2001     1 ttys004     12.5 /Users/me/.local/share/claude/versions/2.1.181/claude --resume
     5793  1275 ??           0.0 /Applications/Claude.app/Contents/Helpers/disclaimer /Users/me/Library/Application Support/Claude/claude-code/2.1.170/claude.app/Contents/MacOS/claude --output-format stream-json
     5794  5793 ??           2.6 /Users/me/Library/Application Support/Claude/claude-code/2.1.170/claude.app/Contents/MacOS/claude --output-format stream-json --model claude-opus-4-8
     1275     1 ??           0.2 /Applications/Claude.app/Contents/MacOS/Claude
     1354     1 ??           0.0 /Applications/Claude.app/Contents/Frameworks/Electron Framework.framework/Helpers/chrome_crashpad_handler --no-rate-limit --database=/Users/me/Library/Application Support/Claude/Crashpad
     1810  1275 ??          14.2 /Applications/Claude.app/Contents/Frameworks/Claude Helper.app/Contents/MacOS/Claude Helper --type=gpu-process --user-data-dir=/Users/me/Library/Application Support/Claude
     2253  1275 ??          16.1 /Applications/Claude.app/Contents/Frameworks/Claude Helper (Renderer).app/Contents/MacOS/Claude Helper (Renderer) --type=renderer --user-data-dir=/Users/me/Library/Application Support/Claude
     8033     1 ??           0.0 /Applications/Claude.app/Contents/Frameworks/Squirrel.framework/Resources/ShipIt com.anthropic.claudefordesktop.ShipIt /Users/me/Library/Caches/com.anthropic.claudefordesktop.ShipIt/ShipItState.plist
    54194     1 ??           0.0 /Users/me/.local/bin/claude daemon run --origin transient --spawned-by {"label":"claude agents","cwd":"/Users/me/Projects/x","pid":54183}
    54210 54194 ??           0.0 /Users/me/.local/share/claude/versions/2.1.181 --bg-pty-host /tmp/cc-daemon-501/73dbe395/spare/7ff445ad.pty.sock 200 50 -- /Users/me/.local/share/claude/versions/2.1.181 --bg-spare /tmp/cc-daemon-501/73dbe395/spare/7ff445ad.claim.sock
    54222 54210 ??           0.1 /Users/me/.local/share/claude/versions/2.1.181 --bg-spare /tmp/cc-daemon-501/73dbe395/spare/7ff445ad.claim.sock
    60651     1 ??           0.0 /private/var/folders/rc/T/AppTranslocation/ABC/d/Claude Usage.app/Contents/MacOS/Claude Usage
    """

    private func scanner(ps: String, cwd: [Int: String] = [:]) -> ProcessScanner {
        ProcessScanner(listProcesses: { ps }, resolveCwd: { pid in cwd[pid] })
    }

    @Test func keepsOnlyGenuineSessions() {
        let records = scanner(ps: psFixture).scan()
        let pids = Set(records.map(\.pid))
        // Genuine: CLI claude (2001), disclaimer-launched claude-code (5793 wrapper +
        // 5794 binary). The wrapper's command names the real claude binary, so it counts.
        #expect(pids == [2001, 5793, 5794])
    }

    @Test func filtersDesktopHelpersAndDaemonNoise() {
        let pids = Set(scanner(ps: psFixture).scan().map(\.pid))
        // Electron main, crashpad, helpers, Squirrel/ShipIt, daemon, bg workers, Usage.
        for noise in [1275, 1354, 1810, 2253, 8033, 54194, 54210, 54222, 60651] {
            #expect(!pids.contains(noise), "pid \(noise) should be filtered out")
        }
    }

    @Test func parsesFieldsForCLISession() {
        let rec = scanner(ps: psFixture).scan().first { $0.pid == 2001 }
        #expect(rec != nil)
        #expect(rec?.ppid == 1)
        #expect(rec?.tty == "ttys004")
        #expect(rec?.cpu == 12.5)
    }

    @Test func ttyIsNilForNonTerminalProcess() {
        // "??" in the TTY column means no controlling terminal (GUI/daemon-launched).
        let rec = scanner(ps: psFixture).scan().first { $0.pid == 5794 }
        #expect(rec != nil)
        #expect(rec?.tty == nil)
        #expect(rec?.ppid == 5793)
    }

    @Test func cwdComesFromInjectedResolver() {
        let s = scanner(ps: psFixture, cwd: [2001: "/Users/me/Projects/api"])
        let rec = s.scan().first { $0.pid == 2001 }
        #expect(rec?.cwd == "/Users/me/Projects/api")
        // No resolver entry → cwd nil, not a crash.
        #expect(s.scan().first { $0.pid == 5794 }?.cwd == nil)
    }

    @Test func toleratesBlankLinesAndKeepsHeaderOut() {
        let ps = """

          PID  PPID TTY         %CPU COMMAND
         2001     1 ttys004     12.5 /Users/me/.local/share/claude/versions/2.1.181/claude

        """
        let records = scanner(ps: ps).scan()
        #expect(records.count == 1)
        #expect(records.first?.pid == 2001)
    }

    @Test func emptyOutputYieldsNoRecords() {
        #expect(scanner(ps: "").scan().isEmpty)
        #expect(scanner(ps: "  PID  PPID TTY  %CPU COMMAND\n").scan().isEmpty)
    }

    @Test func parsesCpuWithDeviceStyleTTY() {
        // ps may print a bare device like "s004" or a full "ttys004"; both normalize.
        let ps = """
          PID  PPID TTY         %CPU COMMAND
         3100     1 s004         0.0 /Users/me/.local/bin/claude
        """
        let rec = scanner(ps: ps).scan().first
        #expect(rec?.tty == "ttys004")
    }
}
