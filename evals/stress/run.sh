#!/bin/bash
# evals/stress/run.sh — one-shot stress-test runner.
#
# Usage:
#   ./evals/stress/run.sh <id>           # id is 1, 2, or 3
#   ./evals/stress/run.sh 2 --keep       # don't delete sandbox afterwards
#
# What it does:
#   1. Creates a fresh sandbox dir in /tmp/anchor-stress-<id>-<ts>/
#   2. Copies the fixture from evals/stress/fixtures/<id>-<name>/ (if any)
#   3. git init + initial commit
#   4. Runs codex exec with the stress test's prompt (extracted from spec)
#   5. Extracts the assistant transcript from codex's JSON stream
#   6. Runs grade.py to produce a markdown report via codex-as-judge
#   7. Prints the report path and a summary
#
# Requires: codex CLI on PATH, python3, git.

set -e

ID="${1:-}"
KEEP_FLAG="${2:-}"

if [ -z "$ID" ] || ! [[ "$ID" =~ ^[123]$ ]]; then
    cat <<'USAGE'
Usage: ./evals/stress/run.sh <id> [--keep]
  id:    1 (scaffold), 2 (refactor), 3 (debug)
  --keep don't delete the sandbox dir after running
USAGE
    exit 1
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TS="$(date +%s)"
SANDBOX="/tmp/anchor-stress-${ID}-${TS}"
SPEC_FILE="$(find "$REPO_ROOT/evals/stress" -maxdepth 1 -name "0${ID}-*.md" | head -1)"

if [ -z "$SPEC_FILE" ]; then
    echo "ERROR: no spec found for stress test #$ID under evals/stress/" >&2
    exit 1
fi

echo "Stress test #$ID — $(basename "$SPEC_FILE" .md)"
echo "Sandbox: $SANDBOX"
echo ""

# ---- 1. Build sandbox + fixture ----
mkdir -p "$SANDBOX"
cd "$SANDBOX"
git init -q
git config user.email "test@local"
git config user.name "test"

case "$ID" in
    1)
        # Stress #1 is a scaffold task — start from empty repo
        git -c commit.gpgsign=false commit --allow-empty -q -m "stress test #1 start"
        ;;
    2)
        cp -r "$REPO_ROOT/evals/stress/fixtures/02-refactor/." .
        git add . && git -c commit.gpgsign=false commit -q -m "fixture: tangled order processor"
        ;;
    3)
        cp -r "$REPO_ROOT/evals/stress/fixtures/03-debug/." .
        git add . && git -c commit.gpgsign=false commit -q -m "fixture: textproc with 3 known bugs"
        ;;
esac

echo "  ✓ sandbox + fixture prepared"

# ---- 2. Extract the prompt from the spec ----
# The spec has a "## Prompt (paste verbatim)" section followed by a > quoted block.
PROMPT_FILE="$SANDBOX/.prompt.txt"
python3 - "$SPEC_FILE" "$PROMPT_FILE" <<'PYEOF'
import re, sys
from pathlib import Path
spec = Path(sys.argv[1]).read_text()
out = Path(sys.argv[2])
# Find the "## Prompt (paste verbatim)" section
m = re.search(r"^##\s+Prompt\s*\(paste verbatim\)\s*$([\s\S]*?)(?=^##\s|\Z)", spec, re.M)
if not m:
    sys.exit("could not locate Prompt section in spec")
body = m.group(1)
# Strip blockquote ">" markers
lines = []
for line in body.splitlines():
    if line.startswith("> "):
        lines.append(line[2:])
    elif line.strip() == ">":
        lines.append("")
prompt = "\n".join(lines).strip()
out.write_text(prompt)
print(f"  ✓ prompt extracted ({len(prompt)} chars)", file=sys.stderr)
PYEOF

PROMPT="$(cat "$PROMPT_FILE")"
rm -f "$PROMPT_FILE"

# ---- 3. Run codex exec ----
echo "  → running codex exec (this can take 10-30 minutes)..."
codex exec --json --skip-git-repo-check --sandbox workspace-write "$PROMPT" \
    > "$SANDBOX/codex-output.json" 2>&1

# ---- 4. Extract transcript ----
python3 - "$SANDBOX/codex-output.json" "$SANDBOX/transcript.txt" <<'PYEOF'
import json, sys
parts = []
for line in open(sys.argv[1]):
    line = line.strip()
    if not line:
        continue
    try:
        d = json.loads(line)
    except Exception:
        continue
    if d.get("type") == "item.completed":
        t = d.get("item", {}).get("text", "")
        if t:
            parts.append(t)
out = "\n\n---\n\n".join(parts)
open(sys.argv[2], "w").write(out)
print(f"  ✓ transcript extracted ({len(out)} chars, {len(parts)} events)", file=sys.stderr)
PYEOF

# ---- 5. Grade ----
echo "  → grading via codex-as-judge..."
python3 "$REPO_ROOT/evals/stress/grade.py" \
    --stress-id "$ID" \
    --transcript "$SANDBOX/transcript.txt" \
    --sandbox "$SANDBOX" \
    --output "$SANDBOX/grading.md"

# ---- 6. Summary ----
echo ""
echo "─────────────────────────────"
SCORE_LINE=$(grep -E "^\*\*Score\*\*" "$SANDBOX/grading.md" | head -1)
echo "$SCORE_LINE"
echo ""
echo "Full report: $SANDBOX/grading.md"
echo "Transcript:  $SANDBOX/transcript.txt"
echo "Sandbox:     $SANDBOX"

# ---- 7. Cleanup (optional) ----
if [ "$KEEP_FLAG" != "--keep" ]; then
    echo ""
    echo "Run with '--keep' to preserve sandbox; ./evals/stress/run.sh $ID --keep"
fi
