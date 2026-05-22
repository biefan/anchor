#!/bin/bash
# Comprehensive test for anchor v1.9.0 — exercise all hooks + commands + memory loop.
# Run from repo root. Validates Phase 1 (functional) before promoting to release.
#
# shellcheck disable=SC2015,SC2012,SC2181
# Rationale: A && B || C idiom is fine for test assertions where both B and C
# are single function calls with no side-effect ordering concerns. ls + wc is
# fine for counting files we control. $? indirection is fine after a single
# command. Switching to if/else would 2x line count for zero behavior change.

set +e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for _candidate in \
    "$HOME/.claude/skills/anchor/scripts" \
    "$SCRIPT_DIR/../../skills/anchor/scripts" \
    "skills/anchor/scripts"; do
    if [ -f "$_candidate/pre-tool-danger.sh" ]; then HOOK_DIR="$_candidate"; break; fi
done
HOOK_DIR="${HOOK_DIR:-skills/anchor/scripts}"
CMDS_DIR="$SCRIPT_DIR/../../commands"
[ -d "$CMDS_DIR" ] || CMDS_DIR="commands"
REPO_ROOT="$SCRIPT_DIR/../.."
TMPHOME="/tmp/anchor-test-home-$$"
mkdir -p "$TMPHOME/.claude/skills" "$TMPHOME/.claude/commands" "$TMPHOME/.anchor"

pass=0
fail=0
check() {
    local desc=$1
    local result=$2
    if [ "$result" = "PASS" ]; then
        echo "  ✓ $desc"
        pass=$((pass+1))
    else
        echo "  ✗ $desc"
        fail=$((fail+1))
    fi
}

echo "=== Section A: Hook scripts execute without error ==="

# A1: session-start-inject.sh — no project state, basic
out=$(echo '{"cwd":"/tmp"}' | HOME="$TMPHOME" bash "$HOOK_DIR/session-start-inject.sh" 2>&1)
echo "$out" | grep -q "Efficient-Coding Context" && check "A1 session-start basic output" PASS || check "A1 session-start basic output" FAIL

# A2: session-start with autonomous flag
touch "$TMPHOME/.claude/.efficient-coding-autonomous"
out=$(echo '{"cwd":"/tmp"}' | HOME="$TMPHOME" bash "$HOOK_DIR/session-start-inject.sh" 2>&1)
echo "$out" | grep -q "Autonomous mode.*ENABLED" && check "A2 session-start autonomous detected" PASS || check "A2 session-start autonomous detected" FAIL
rm "$TMPHOME/.claude/.efficient-coding-autonomous"

# A3: session-start with lean mode
touch "$TMPHOME/.claude/.anchor-lean"
out=$(echo '{"cwd":"/tmp"}' | HOME="$TMPHOME" bash "$HOOK_DIR/session-start-inject.sh" 2>&1)
echo "$out" | grep -q "lean mode" && check "A3 session-start lean mode acknowledged" PASS || check "A3 session-start lean mode acknowledged" FAIL
rm "$TMPHOME/.claude/.anchor-lean"

# A4: stop-self-check — no autonomous, no task dir → exit 0 quietly
out=$(echo '{"session_id":"test"}' | HOME="$TMPHOME" bash "$HOOK_DIR/stop-self-check.sh" 2>&1)
[ -z "$out" ] && check "A4 stop hook quiet when autonomous off" PASS || check "A4 stop hook quiet when autonomous off" FAIL

# A5: stop-self-check — autonomous + tasks pending → block
touch "$TMPHOME/.claude/.efficient-coding-autonomous"
mkdir -p "$TMPHOME/.claude/tasks/test-session"
echo '{"id":"1","status":"pending","subject":"test task"}' > "$TMPHOME/.claude/tasks/test-session/1.json"
out=$(echo '{"session_id":"test-session"}' | HOME="$TMPHOME" bash "$HOOK_DIR/stop-self-check.sh" 2>&1)
echo "$out" | grep -q '"decision": "block"' && check "A5 stop hook blocks pending tasks in autonomous" PASS || check "A5 stop hook blocks pending tasks in autonomous" FAIL
rm -rf "$TMPHOME/.claude/tasks/test-session"
rm "$TMPHOME/.claude/.efficient-coding-autonomous"

# A6: pre-compact-warning — autonomous + pending → warn
mkdir -p "$TMPHOME/.claude/tasks/compact-test"
echo '{"id":"1","status":"in_progress","subject":"long task"}' > "$TMPHOME/.claude/tasks/compact-test/1.json"
out=$(echo '{"session_id":"compact-test"}' | HOME="$TMPHOME" bash "$HOOK_DIR/pre-compact-warning.sh" 2>&1)
echo "$out" | grep -q "PreCompact warning" && check "A6 pre-compact warns on pending tasks" PASS || check "A6 pre-compact warns on pending tasks" FAIL
rm -rf "$TMPHOME/.claude/tasks/compact-test"

# A7: pre-tool-danger — basic block still works (regression check)
out=$(echo '{"tool_name":"Bash","tool_input":{"command":"rm -rf /"}}' | bash "$HOOK_DIR/pre-tool-danger.sh" 2>&1)
echo "$out" | grep -q '"decision": "block"' && check "A7 pre-tool danger blocks rm -rf /" PASS || check "A7 pre-tool danger blocks rm -rf /" FAIL

# A8: post-tool-lint — JSON file with single quote name (v1.3.6 fix verification)
cat > "/tmp/don't-test-$$.json" <<EOF
{}
EOF
out=$(printf '%s' "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"/tmp/don't-test-$$.json\"}}" | bash "$HOOK_DIR/post-tool-lint.sh" 2>&1)
[ -z "$out" ] && check "A8 post-tool lint quiet on clean JSON with weird filename" PASS || check "A8 post-tool lint quiet on clean JSON with weird filename" FAIL
rm -f "/tmp/don't-test-$$.json"

echo ""
echo "=== Section B: Helper scripts ==="

# B1: analyze-events.py runs without crash
out=$(python3 "$HOOK_DIR/analyze-events.py" --all 2>&1 | head -3)
echo "$out" | grep -q "anchor events" && check "B1 analyze-events outputs summary header" PASS || check "B1 analyze-events outputs summary header" FAIL

# B2: pitfall-sync.py with synthetic CLAUDE.md
testdir="/tmp/pitfall-test-$$"
mkdir -p "$testdir"
cat > "$testdir/CLAUDE.md" <<'EOF'
# Test Project

## 踩坑记录

### Test bug A (2026-05-22)
- **现象**: 测试现象
- **根因**: 测试根因
- **修复**: 测试修复
- **教训**: 测试教训
EOF
out=$(HOME="$TMPHOME" python3 "$HOOK_DIR/pitfall-sync.py" --project test --cwd "$testdir" 2>&1)
echo "$out" | grep -q "synced" && check "B2 pitfall-sync extracts entry" PASS || check "B2 pitfall-sync extracts entry" FAIL
[ -d "$TMPHOME/.anchor/memory/pitfalls/test" ] && check "B2' pitfall-sync writes to memory tree" PASS || check "B2' pitfall-sync writes to memory tree" FAIL
rm -rf "$testdir"

echo ""
echo "=== Section C: Memory loop (write → index → recall) ==="

# C1: create fake pitfall + decision + fact, then verify SessionStart memory index lists them
proj="lp-test-$$"
mkdir -p "$TMPHOME/.anchor/memory/pitfalls/$proj"
mkdir -p "$TMPHOME/.anchor/memory/decisions/$proj"
mkdir -p "$TMPHOME/.anchor/memory/facts/$proj"

cat > "$TMPHOME/.anchor/memory/pitfalls/$proj/2026-05-20-redis-cluster.md" <<'EOF'
# Redis cluster slot mismatch
- Project: lp-test
- Date: 2026-05-20
EOF
cat > "$TMPHOME/.anchor/memory/decisions/$proj/2026-05-15-redis-vs-rabbitmq.md" <<'EOF'
# Redis Streams over RabbitMQ
- Project: lp-test
- Date: 2026-05-15
EOF
cat > "$TMPHOME/.anchor/memory/facts/$proj/2026-05-10-prod-db.md" <<'EOF'
# Prod DB endpoint
- Project: lp-test
EOF

# Create project dir matching slug
projdir="/tmp/$proj"
mkdir -p "$projdir"

out=$(echo "{\"cwd\":\"$projdir\"}" | HOME="$TMPHOME" bash "$HOOK_DIR/session-start-inject.sh" 2>&1)
echo "$out" | grep -q "Memory index" && check "C1 SessionStart shows Memory index header" PASS || check "C1 SessionStart shows Memory index header" FAIL
echo "$out" | grep -q "Redis cluster" && check "C2 Memory index lists pitfall title" PASS || check "C2 Memory index lists pitfall title" FAIL
echo "$out" | grep -q "Redis Streams" && check "C3 Memory index lists decision title" PASS || check "C3 Memory index lists decision title" FAIL
echo "$out" | grep -q "Prod DB" && check "C4 Memory index lists fact title" PASS || check "C4 Memory index lists fact title" FAIL
echo "$out" | grep -q "Auto-recall reflex" && check "C5 Memory index includes auto-recall reflex tip" PASS || check "C5 Memory index includes auto-recall reflex tip" FAIL

# C6: lean mode skips memory index
touch "$TMPHOME/.claude/.anchor-lean"
out=$(echo "{\"cwd\":\"$projdir\"}" | HOME="$TMPHOME" bash "$HOOK_DIR/session-start-inject.sh" 2>&1)
echo "$out" | grep -q "Memory index" && check "C6 lean mode SKIPS memory index (negative test)" FAIL || check "C6 lean mode SKIPS memory index (negative test)" PASS
rm "$TMPHOME/.claude/.anchor-lean"

# C7: preferences auto-inject when file has content
cat > "$TMPHOME/.anchor/memory/preferences.md" <<'EOF'
# My preferences

- 我用 pnpm 不是 npm
- 代码注释默认中文
- 测试用 pytest 不是 unittest
EOF
out=$(echo "{\"cwd\":\"$projdir\"}" | HOME="$TMPHOME" bash "$HOOK_DIR/session-start-inject.sh" 2>&1)
echo "$out" | grep -q "User preferences" && check "C7 preferences auto-inject when non-empty" PASS || check "C7 preferences auto-inject when non-empty" FAIL
echo "$out" | grep -q "pnpm" && check "C7' preferences content actually appears" PASS || check "C7' preferences content actually appears" FAIL

# C8: empty preferences NOT injected
echo "" > "$TMPHOME/.anchor/memory/preferences.md"
out=$(echo "{\"cwd\":\"$projdir\"}" | HOME="$TMPHOME" bash "$HOOK_DIR/session-start-inject.sh" 2>&1)
echo "$out" | grep -q "User preferences" && check "C8 empty preferences SKIPPED" FAIL || check "C8 empty preferences SKIPPED" PASS

# Cleanup C section
rm -rf "$TMPHOME/.anchor/memory/pitfalls/$proj" "$TMPHOME/.anchor/memory/decisions/$proj" "$TMPHOME/.anchor/memory/facts/$proj"
rm -f "$TMPHOME/.anchor/memory/preferences.md"
rm -rf "$projdir"

echo ""
echo "=== Section D: Command file syntax ==="

# D1: All command .md files have valid frontmatter
for f in "$CMDS_DIR"/*.md; do
    head -1 "$f" | grep -q '^---$' && head -10 "$f" | grep -q '^description:' || { check "D1 $f frontmatter" FAIL; continue; }
done
check "D1 all command frontmatters present" PASS

# D2: No command file is empty
for f in "$CMDS_DIR"/*.md; do
    [ -s "$f" ] || { check "D2 $f non-empty" FAIL; continue; }
done
check "D2 all command files non-empty" PASS

# D3: Count of commands matches expected (v1.13.0 = 23, was 22 before /strict)
count=$(ls "$CMDS_DIR"/*.md | wc -l | tr -d ' ')
[ "$count" -eq 23 ] && check "D3 23 commands present" PASS || check "D3 23 commands present (got $count)" FAIL

echo ""
echo "=== Section E: Templates ==="

# E1: 5 templates exist
TMPL_DIR="$REPO_ROOT/skills/anchor/references/templates"
for t in web-app library cli-tool data-pipeline default; do
    [ -f "$TMPL_DIR/$t.md" ] && [ -s "$TMPL_DIR/$t.md" ] && continue
    check "E1 template $t exists" FAIL
done
check "E1 all 5 templates exist + non-empty" PASS

echo ""
echo "=== Section F: install.sh / uninstall.sh idempotency ==="

# F1: install.sh exits 0
TEST_HOME="/tmp/anchor-install-test-$$"
mkdir -p "$TEST_HOME"
HOME="$TEST_HOME" bash "$REPO_ROOT/install.sh" --no-hooks > /dev/null 2>&1
[ $? -eq 0 ] && check "F1 install.sh --no-hooks exits 0" PASS || check "F1 install.sh --no-hooks exits 0" FAIL

# F2: install.sh creates skill dir
[ -d "$TEST_HOME/.claude/skills/anchor" ] && check "F2 install creates skills/anchor/" PASS || check "F2 install creates skills/anchor/" FAIL

# F3: 23 commands installed (v1.13.0 added /strict)
installed_cmds=$(find "$TEST_HOME/.claude/commands" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
[ "$installed_cmds" -eq 23 ] && check "F3 23 commands installed" PASS || check "F3 23 commands installed (got $installed_cmds)" FAIL

# F4: templates installed
[ -d "$TEST_HOME/.claude/skills/anchor/references/templates" ] && check "F4 templates dir installed" PASS || check "F4 templates dir installed" FAIL

# F5: pitfall-sync.py installed
[ -x "$TEST_HOME/.claude/skills/anchor/scripts/pitfall-sync.py" ] && check "F5 pitfall-sync.py installed + executable" PASS || check "F5 pitfall-sync.py installed + executable" FAIL

# F6: re-run install — idempotent
HOME="$TEST_HOME" bash "$REPO_ROOT/install.sh" --no-hooks > /dev/null 2>&1
[ $? -eq 0 ] && check "F6 install re-run idempotent (exits 0)" PASS || check "F6 install re-run idempotent (exits 0)" FAIL

# F7: uninstall
HOME="$TEST_HOME" bash "$REPO_ROOT/uninstall.sh" > /dev/null 2>&1
[ $? -eq 0 ] && check "F7 uninstall exits 0" PASS || check "F7 uninstall exits 0" FAIL
[ ! -d "$TEST_HOME/.claude/skills/anchor" ] && check "F7' uninstall removed skill dir" PASS || check "F7' uninstall removed skill dir" FAIL

# Cleanup
rm -rf "$TEST_HOME"

echo ""
echo "=== Section G: Plugin manifest validity ==="

# G1: All plugin.json files are valid + version-consistent
v1=$(python3 -c "import json; print(json.load(open('$REPO_ROOT/.claude-plugin/plugin.json'))['version'])" 2>/dev/null)
v2=$(python3 -c "import json; print(json.load(open('$REPO_ROOT/.codex-plugin/plugin.json'))['version'])" 2>/dev/null)
v3=$(python3 -c "import json; print(json.load(open('$REPO_ROOT/.claude-plugin/marketplace.json'))['metadata']['version'])" 2>/dev/null)
if [ "$v1" = "$v2" ] && [ "$v2" = "$v3" ] && [ -n "$v1" ]; then
    check "G1 3 plugin manifests version-consistent ($v1)" PASS
else
    check "G1 3 plugin manifests version-consistent (got $v1/$v2/$v3)" FAIL
fi

# G2: claude-plugin has interface section (required by awesome-codex-plugins)
if python3 -c "import json; d=json.load(open('$REPO_ROOT/.codex-plugin/plugin.json')); assert 'interface' in d" 2>/dev/null; then
    check "G2 codex-plugin has interface block" PASS
else
    check "G2 codex-plugin has interface block" FAIL
fi

echo ""
echo "=== Cleanup ==="
rm -rf "$TMPHOME"

echo ""
echo "─────────────────────────────────────"
echo "Result: $pass passed, $fail failed (out of $((pass+fail)))"
if [ $fail -eq 0 ]; then
    echo "✅ All comprehensive tests passed"
    exit 0
else
    echo "❌ $fail failure(s) — see above"
    exit 1
fi
