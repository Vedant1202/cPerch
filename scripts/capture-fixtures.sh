#!/usr/bin/env bash
# Capture SANITIZED ~/.claude fixtures for cPerch tests into Tests/fixtures/local/
# (gitignored). Registry entries get home paths redacted; transcript tails keep
# structure but strip message text/thinking content. Never commit raw user data.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/Tests/fixtures/local"
mkdir -p "$DEST/registry" "$DEST/transcripts"

# Registry entries (metadata; redact /Users/<name> → /Users/USER)
for f in "$HOME"/.claude/sessions/*.json; do
  [ -e "$f" ] || continue
  python3 - "$f" "$DEST/registry/$(basename "$f")" <<'PY'
import json, re, sys
src, dst = sys.argv[1], sys.argv[2]
try: d = json.load(open(src))
except Exception: sys.exit(0)
if isinstance(d.get("cwd"), str):
    d["cwd"] = re.sub(r"/Users/[^/]+", "/Users/USER", d["cwd"])
json.dump(d, open(dst, "w"), indent=2)
PY
done

# Transcript tails (last 40 records; strip text/thinking/tool_result content)
for f in "$HOME"/.claude/projects/*/*.jsonl; do
  [ -e "$f" ] || continue
  out="$DEST/transcripts/$(basename "$(dirname "$f")")__$(basename "$f")"
  tail -n 40 "$f" | python3 - "$out" <<'PY'
import json, sys
out = sys.argv[1]; lines = []
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    try: o = json.loads(line)
    except Exception: continue
    m = o.get("message")
    if isinstance(m, dict):
        c = m.get("content")
        if isinstance(c, list):
            for x in c:
                if not isinstance(x, dict): continue
                if x.get("type") == "text": x["text"] = "<redacted>"
                if x.get("type") == "thinking": x["thinking"] = "<redacted>"
                if x.get("type") == "tool_result" and isinstance(x.get("content"), str):
                    x["content"] = "<redacted>"
        elif isinstance(c, str):
            m["content"] = "<redacted>"
    lines.append(json.dumps(o))
open(out, "w").write("\n".join(lines))
PY
done

echo "Captured sanitized fixtures → $DEST"
