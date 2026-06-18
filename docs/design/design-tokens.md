# cPerch — design tokens

Goal: feel consistent with the Claude app. Values below come from **Anthropic's official
`brand-guidelines` skill** (authoritative) plus documented Claude.ai brand specs. They can be
fine-tuned against the live app when the UI is built.

## Status colors

The three statuses map onto Anthropic's three official **accent** colors — on-brand and instantly
distinguishable:

| Status | Token | Hex | Source |
|---|---|---|---|
| 🟠 needs-input | `--status-needs-input` | `#d97757` | Anthropic accent — Orange (primary) |
| 🔵 running | `--status-running` | `#6a9bcc` | Anthropic accent — Blue (secondary) |
| 🟢 concluded | `--status-concluded` | `#788c5d` | Anthropic accent — Green (tertiary) |

Rationale: orange is Claude's signature and the most attention-grabbing, so it's reserved for the
state that actually needs the human. Blue reads "in progress." Green reads "done."

## Neutrals (surfaces & text)

| Role | Hex | Anthropic name |
|---|---|---|
| Ink / primary text, dark surfaces | `#141413` | Dark |
| Paper / light surface | `#faf9f5` | Light |
| Secondary text / icons | `#b0aea5` | Mid Gray |
| Subtle fills / dividers | `#e8e6dc` | Light Gray |

Brand coral variants (buttons / hover, from Claude.ai specs): primary `#da7756` (≈ accent orange),
pressed/hover `#bd5d3a`. Warm cream alt background `#eeece2`; warm ink text `#3d3929`.

> `#d97757` (Anthropic skill) and `#da7756` (Claude.ai brand spec) are the same coral to within
> rounding — use **`#d97757`** as the canonical token.

## Typography

Claude's real UI faces — **Styrene B** (body/UI) and **Copernicus** (display) — are proprietary and
can't be bundled. Closest free substitutes:

| Role | Font | Fallback stack |
|---|---|---|
| UI / body | **Inter** (≈ Styrene B) | `Inter, -apple-system, "SF Pro Text", system-ui, sans-serif` |
| Code / message mono | **JetBrains Mono** (matches Claude) | `"JetBrains Mono", "SF Mono", ui-monospace, monospace` |

For a native menu-bar feel with zero bundling, **SF Pro** (the system font) is an acceptable default;
bundle **Inter** when brand fidelity matters more than footprint.

## Dark mode

The dropdown should follow the system appearance. Light: paper `#faf9f5` surface, ink `#141413` text.
Dark: ink `#141413` surface, paper `#faf9f5` text. The accent status dots stay the same in both (they
read well on either). Tune contrast when implemented.

## Sources

- Anthropic official `brand-guidelines` skill — `github.com/anthropics/skills`
- Claude.ai brand color & font specs (documented third-party brand references)
