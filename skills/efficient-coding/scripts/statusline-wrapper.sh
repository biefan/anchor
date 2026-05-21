#!/bin/bash
# Example statusline wrapper: runs existing ccstatusline and appends ec-status.
# To use:
#   1. Make sure ec-status.sh is executable
#   2. In ~/.claude/settings.json, set:
#      "statusLine": {
#        "type": "command",
#        "command": "bash \"$HOME/.claude/skills/efficient-coding/scripts/statusline-wrapper.sh\""
#      }
# If you're not using ccstatusline, edit MAIN below to your own statusline command.

# Read the input once and reuse it
input=$(cat)

# MAIN: keep existing statusline behavior
main=$(echo "$input" | npx -y ccstatusline@latest 2>/dev/null)

# EC: append our status
ec=$(echo "$input" | bash "$HOME/.claude/skills/efficient-coding/scripts/ec-status.sh" 2>/dev/null)

# Print combined
if [ -n "$ec" ]; then
    echo "$main · $ec"
else
    echo "$main"
fi
