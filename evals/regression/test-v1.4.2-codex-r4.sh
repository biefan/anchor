#!/bin/bash
# Regression suite for codex r4 findings E1-E11.
HOOK=skills/anchor/scripts/pre-tool-danger.sh

TESTS=(
    "BLOCK::rm -rf /e*::E1 glob /e* expanding to /etc"
    "BLOCK::rm -rf /??c::E1 ?? glob"
    "BLOCK::rm -rf /[a-z]tc::E1 char class glob"
    "BLOCK::rm -rf /tmp/../etc::E2 normpath /tmp/../etc → /etc"
    "BLOCK::rm -rf /var/log/../etc/passwd::E2 normpath deeper"
    "BLOCK::printf 'rm -rf /' |& bash::E3 |& bash pipe"
    "BLOCK::cat > >(rm -rf /tmp/x \$HOME)::E4 process substitution >()"
    "BLOCK::env -S 'rm -rf /' ls::E5 env -S string"
    "BLOCK::su -c 'rm -rf /'::E6 su -c (was unwrapped)"
    "BLOCK::watch 'rm -rf /'::E7 watch quoted cmd"
    "BLOCK::taskset 0x3 rm -rf /::E8 taskset CPU mask leading positional"
    "BLOCK::chrt -f 99 rm -rf /::E8 chrt -f policy"
    "BLOCK::parallel 'rm -rf /' ::: a b c::E9 parallel template"
    "BLOCK::flock /tmp/l rm -rf /::E10 flock wrapper"
    "BLOCK::nohup rm -rf / &::E10 nohup wrapper"
    "BLOCK::setsid rm -rf /::E10 setsid wrapper"
    "BLOCK::runuser -u root -- rm -rf /::E10 runuser wrapper"
    "BLOCK::echo data >| /dev/sda::E11 >| write to disk"
    "BLOCK::tee /dev/nvme0n1::E11 tee to nvme"
    "BLOCK::cat foo | tee /dev/sda::E11 tee in pipeline"
    # Regression: ensure normal cases still pass
    "PASS::echo hello::reg plain echo"
    "PASS::rm -rf /tmp/myfile::reg user-tmp cleanup"
    "PASS::cat /etc/hostname::reg plain cat"
    "PASS::find /tmp -name '*.log'::reg find no -exec destructive"
    "PASS::tee /tmp/log.txt::reg tee to user file"
)

pass=0
fail=0
for entry in "${TESTS[@]}"; do
    expect=$(echo "$entry" | awk -F'::' '{print $1}')
    cmd=$(echo "$entry" | awk -F'::' '{print $2}')
    desc=$(echo "$entry" | awk -F'::' '{print $3}')
    json_cmd=$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$cmd")
    out=$(printf '%s' "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":$json_cmd}}" | bash "$HOOK" 2>&1)
    if echo "$out" | grep -q '"decision": "block"'; then actual=BLOCK; else actual=PASS; fi
    if [ "$actual" = "$expect" ]; then
        echo "  ✓ $desc"
        pass=$((pass+1))
    else
        echo "  ✗ $desc → $actual, expected $expect"
        echo "    cmd: $cmd"
        out_clean=$(echo "$out" | head -c 200)
        echo "    out: $out_clean"
        fail=$((fail+1))
    fi
done
echo ""
echo "Result: $pass / ${#TESTS[@]} pass"
