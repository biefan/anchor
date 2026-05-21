# shellcheck shell=bash
# Helper for hooks to append a structured JSON line to ~/.claude/anchor-events.jsonl.
# Sourced by other hook scripts. Never causes the caller to fail — write errors are swallowed.
#
# Usage:
#   EC_LOG_event="stop_blocked" \
#   EC_LOG_session_id="$session_id" \
#   EC_LOG_pending_count="3" \
#   ec_log_event
#
# Every key prefixed with EC_LOG_ becomes a top-level JSON field (with the prefix stripped).
# A `ts` field (ISO 8601 UTC) is added automatically.

ec_log_event() {
    python3 - <<'PYEOF' 2>/dev/null || true
import fcntl, json, os, time
try:
    p = os.path.expanduser("~/.claude/anchor-events.jsonl")
    os.makedirs(os.path.dirname(p), exist_ok=True)
    prefix = "EC_LOG_"
    d = {k[len(prefix):]: v for k, v in os.environ.items() if k.startswith(prefix)}
    d["ts"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    line = json.dumps(d, ensure_ascii=False) + "\n"
    # Lock the file before appending so concurrent hooks can't interleave bytes
    # inside a single JSON line. flock auto-releases when fd closes.
    with open(p, "a") as f:
        try:
            fcntl.flock(f.fileno(), fcntl.LOCK_EX)
        except OSError:
            pass  # filesystem may not support flock; best-effort
        f.write(line)
except Exception:
    pass
PYEOF
}
