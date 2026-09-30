# Source to get a sandboxed demo: fake HOME, three extra logins, a claude-mem "worker" paused by one of them.
DEMO_SRC="${${(%):-%x}:A:h}"; export DEMO_HOME="${DEMO_HOME:-${TMPDIR:-/tmp}/claude-switchboard-demo}"
rm -rf "$DEMO_HOME"; mkdir -p "$DEMO_HOME/.claude/projects" "$DEMO_HOME/.claude-mem"
export HOME="$DEMO_HOME" CCA_ROOT="$DEMO_HOME/.claude-accounts" CLAUDE_MEM_DATA_DIR="$DEMO_HOME/.claude-mem"
export PATH="$DEMO_SRC/bin:$PATH" CCM_USAGE_URL="http://127.0.0.1:37798/api/oauth/usage"
b="$HOME/.claude/plugins/cache/thedotmack/claude-mem/13.28.0/scripts"; mkdir -p "$b"
printf '/*cwi-ccm-per-account-quota*/\n' > "$b/worker-service.cjs"; export DEMO_BUNDLE="$b/worker-service.cjs"
printf '{"CLAUDE_MEM_WORKER_PORT":"37798","CLAUDE_MEM_CLAUDE_CONFIG_DIR":"%s/work"}' "$CCA_ROOT" > "$CLAUDE_MEM_DATA_DIR/settings.json"
printf '[{"provider":"claude","message":"Provider reported the inference allowance exhausted","window":"seven_day","profile":"work","armedAtMs":%s}]' \
  "$(($(date +%s) * 1000 - 5400000))" > "$CLAUDE_MEM_DATA_DIR/quota-cooldown.json"
source "$DEMO_SRC/../cca.zsh"
for n in work personal client-acme; do cca add "$n" >/dev/null; done
for d in "$HOME/.claude" "$CCA_ROOT"/*(/); do   # Linux reads tokens from files; token = profile name
  n="${d:t}"; [[ $d == $HOME/.claude ]] && n=default
  printf '{"claudeAiOauth":{"accessToken":"%s"}}' "$n" > "$d/.credentials.json"
done
python3 "$DEMO_SRC/fake_server.py" 37798 & DEMO_SERVER=$!
for i in {1..50}; do curl -s -m1 -o /dev/null http://127.0.0.1:37798/api/health && break; sleep 0.2; done   # wait until it answers
