<h1 align="center">🪶 cPerch</h1>

<p align="center"><em>A perch for your Claude sessions.</em></p>

<p align="center">
  <img src="https://img.shields.io/badge/status-W.I.P.-d97757?style=flat-square" alt="Work in progress">
  <img src="https://img.shields.io/badge/macOS-14.0%2B-6a9bcc?style=flat-square" alt="macOS 14+">
  <img src="https://img.shields.io/badge/built%20with-Swift-788c5d?style=flat-square" alt="Built with Swift">
</p>

---

> 🚧 **Early v0** — builds and runs locally as a menu-bar app. No packaged release yet.

**cPerch** is a native macOS menu-bar app that watches your running Claude Code
sessions so you don't have to. One glance at your toolbar tells you which agent
is waiting on you, which is still thinking, and which has wrapped up.

### What it'll do (v0)

- 👀 **See every running session** — across terminals and the Claude desktop app, in one dropdown.
- 🚦 **Know the status at a glance** — 🟠 needs your input · 🔵 running · 🟢 concluded.
- 💬 **Read the latest message** inline, so you know what's being asked without switching windows.
- ↳ **Jump to a session** — one click raises the *existing* window. It never opens a duplicate.

Built to feel like Claude: the same palette, the same type. Light on your machine, quiet in your bar.

### Build & run

Command Line Tools + SwiftPM — no full Xcode:

```bash
./build.sh             # → dist/CPerch.app (ad-hoc signed)
open dist/CPerch.app   # menu-bar agent; click the dot for the roster
./scripts/test.sh      # unit tests (swift-testing)
```

### Status

v0 is functionally complete and runs locally — detection (process + registry + transcript), the
aggregate dot, the roster, jump, and calm notifications all work. No packaged release yet. See
[`docs/ideas/cperch.md`](docs/ideas/cperch.md) for the base camp, [`SPEC.md`](SPEC.md) for the v0
contract, and [`docs/decisions.md`](docs/decisions.md) for the decision log.
