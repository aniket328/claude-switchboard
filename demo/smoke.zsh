#!/usr/bin/env zsh
# Smoke test: runs the real cca/ccm against demo/ stand-ins and checks the account switch resumes the queue.
setopt errexit pipefail
here="${0:A:h}"; source "$here/env.zsh"
trap 'kill $DEMO_SERVER 2>/dev/null' EXIT
fail() { print -u2 "FAIL: $1"; exit 1; }
out="$(cca)";          [[ $out == *"me@work.example"* ]]                 || fail "cca list"
cca work >/dev/null;   [[ $CLAUDE_CONFIG_DIR == "$CCA_ROOT/work" ]]        || fail "cca switch"
out="$(ccm)";          [[ $out == *"PAUSED"*"by work"* ]]                 || fail "ccm shows pause"
                       [[ $out == *"patch: LOADED"* ]]                    || fail "ccm patch state"
out="$(ccm personal)"; [[ $out == *"claude-mem → personal"* ]]           || fail "ccm switch"
grep -q '/personal"' "$CLAUDE_MEM_DATA_DIR/settings.json"                 || fail "settings written"
[[ $CLAUDE_CONFIG_DIR == "$CCA_ROOT/work" ]]                              || fail "ccm must not move this terminal"
out="$(ccm)";          [[ $out != *"PAUSED"* && $out == *"bills: personal"* ]] || fail "pause dropped after switch"
print "smoke: ok"
