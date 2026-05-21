#!/bin/bash
# _runtime.sh — shared helper: detect which CLI runtime is executing the hook.
#
# Usage:  . _runtime.sh && RUNTIME=$(detect_runtime)
#         echo "Runtime: $RUNTIME"  # → "claude-code" | "codex" | "unknown"
#
# Detection order:
#   1. Explicit override via $ANCHOR_RUNTIME env var (user can force)
#   2. Parent process name (most reliable — claude-code / codex binary)
#   3. CLAUDE_CODE_* / CODEX_* env vars (less reliable, runtime-dependent)
#   4. Default: claude-code (anchor's primary target)
#
# shellcheck disable=SC2034
detect_runtime() {
    if [ -n "${ANCHOR_RUNTIME:-}" ]; then
        echo "$ANCHOR_RUNTIME"
        return 0
    fi

    # Check parent process name (PPID is the immediate caller)
    if command -v ps >/dev/null 2>&1; then
        local ppname
        ppname=$(ps -o comm= -p "$PPID" 2>/dev/null | tr -d '[:space:]')
        case "$ppname" in
            *claude*) echo "claude-code"; return 0 ;;
            *codex*)  echo "codex"; return 0 ;;
        esac
        # Also try one level up (in case of intermediate shell)
        local ppid_parent
        ppid_parent=$(ps -o ppid= -p "$PPID" 2>/dev/null | tr -d ' ')
        if [ -n "$ppid_parent" ] && [ "$ppid_parent" != "0" ]; then
            local pppname
            pppname=$(ps -o comm= -p "$ppid_parent" 2>/dev/null | tr -d '[:space:]')
            case "$pppname" in
                *claude*) echo "claude-code"; return 0 ;;
                *codex*)  echo "codex"; return 0 ;;
            esac
        fi
    fi

    # Env var signals (set by some runtimes)
    if [ -n "${CLAUDE_CODE_VERSION:-}" ] || [ -n "${CLAUDE_CODE_SESSION:-}" ]; then
        echo "claude-code"
        return 0
    fi
    if [ -n "${CODEX_VERSION:-}" ] || [ -n "${CODEX_SESSION_ID:-}" ] || [ -n "${CODEX_HOME:-}" ]; then
        echo "codex"
        return 0
    fi

    # Default — anchor's primary target
    echo "claude-code"
}

# Map runtime → tool name hints (for SessionStart hook to inject)
runtime_tool_hints() {
    case "$1" in
        codex)
            cat <<'HINTS'
- Task list: use `plan_tool` / `update_plan` (Codex names) — semantically equivalent to TaskCreate/TaskUpdate
- Asking user: write a clear question in your response (no AskUserQuestion-equivalent in Codex)
- Sub-agents: list them in plan_tool as parallel steps; Codex schedules concurrently
HINTS
            ;;
        claude-code|*)
            cat <<'HINTS'
- Task list: use `TaskCreate` / `TaskUpdate` / `TaskList`
- Asking user: use `AskUserQuestion`
- Sub-agents: use `Agent` (specify subagent_type)
HINTS
            ;;
    esac
}
