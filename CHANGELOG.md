# Changelog

All notable changes to cPerch are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project follows
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
- Release downloads are version-tagged (`CPerch-X.Y.Z.dmg`); the version-less `cPerch-macos.*`
  aliases are gone, and the website's download button points at the latest release page.
- The README release badge now tracks the latest GitHub release automatically, instead of a pinned version.

## [0.7.0] - 2026-06-22

### Added
- **Branding & app icon.** cPerch has a visual identity now — a songbird perched on a terminal
  `>_` prompt. The app ships a real icon (a bundled `.icns`); the menu-bar item shows the bird at
  rest and the colored status glyph when a session is live; and the mark appears in the popover,
  Settings, and Help/About headers. The website (favicon, header and footer, social card) and the
  README carry it too.

## [0.6.0] - 2026-06-19

### Added
- **In-app Help.** A "?" in the menu-bar popover opens a built-in Help panel — what each status icon
  means, the global shortcut (⌘⌥`), an overview of Settings, the accessibility options, a link to the
  privacy policy, and a "Report an issue" flow that copies a short diagnostics summary (cPerch and macOS
  version only — no personal data) before opening the GitHub issue form. Includes an About section and a
  one-time first-run hint.

## [0.5.0] - 2026-06-19

### Added
- **Accessibility.** Status is now shown with a shape *and* a color (not color alone), so states are
  clear in grayscale and for color-vision deficiency. Added a high-contrast mode that follows the macOS
  Increase Contrast setting, VoiceOver labels for the menu-bar item and each session, support for Reduce
  Motion and Reduce Transparency, and a new Accessibility tab in Settings.
- A white plate behind the menu-bar status glyph so it stays visible on any wallpaper.

### Fixed
- Light-mode contrast — secondary text and status indicators now meet WCAG AA.

## [0.4.0] - 2026-06-19

### Added
- Launch cPerch at login (optional, off by default).
- A global hotkey, **⌘⌥`**, to open the session list from any app.
- A richer menu bar: a "needs you" count and an all-done glyph.
- Error and completion notifications (opt-in), with tap-to-open.

## [0.3.0] - 2026-06-18

### Added
- Group the session list by host (Terminal vs the Claude app).
- Configurable retention for how long finished sessions stay in the list.

### Fixed
- Session over-counting — one conversation no longer appears as several rows.

## [0.2.0] - 2026-06-18

### Added
- A Settings window: theme (System / Light / Dark), a simple or grouped list, and notification preferences.
- AI-generated session titles, with disambiguation for same-named projects.
- A message-preview fallback when the latest turn has no text.

### Changed
- More accurate "waiting on you" vs "done" status.

### Fixed
- Working-directory and registry merge fixes (correct names; no missed sessions).

## [0.1.0] - 2026-06-18

### Added
- Initial cPerch — detects running Claude Code sessions from `~/.claude` (process + registry +
  transcript), shows an aggregate menu-bar dot, a session list with status and latest message,
  one-click Jump to the existing window, and calm needs-input notifications. Zero-permission and fully
  local.

### Fixed
- Deduplication and PID-reuse hardening so a recycled process id can't mis-target a jump.

---

_Versions 0.1.0–0.5.0 are backfilled from the project's development history; v0.6.0 is the first tagged
release. Earlier milestones were not published as downloadable builds._
