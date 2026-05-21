#!/bin/bash
# Example statusline wrapper: runs existing ccstatusline and appends ec-status.
# To use:
#   1. Make sure ec-status.sh is executable
#   2. In ~/.claude/settings.json, set:
#      "statusLine": {
#        "type": "command",
#        "command": "bash \"$HOME/.claude/skills/anchor/scripts/statusline-wrapper.sh\""
#      }
# If you're not using ccstatusline, edit MAIN below to your own statusline command.

# Read the input once and reuse it
input=$(cat)

# MAIN: keep existing statusline behavior. Prefer a globally-installed
# ccstatusline binary if present — `npx -y ccstatusline@latest` triggers a
# version check on every status-bar refresh, which is slow on weak networks
# and silently empty offline. Set CCSTATUSLINE_BIN to override.
if [ -n "${CCSTATUSLINE_BIN:-}" ]; then
    main=$(echo "$input" | "$CCSTATUSLINE_BIN" 2>/dev/null)
elif command -v ccstatusline >/dev/null 2>&1; then
    main=$(echo "$input" | ccstatusline 2>/dev/null)
else
    main=$(echo "$input" | npx -y ccstatusline@latest 2>/dev/null)
fi

# EC: append our status
ec=$(echo "$input" | bash "$HOME/.claude/skills/anchor/scripts/ec-status.sh" 2>/dev/null)

# Print combined
if [ -n "$ec" ]; then
    echo "$main · $ec"
else
    echo "$main"
fi
