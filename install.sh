#!/usr/bin/env bash
# claude-switchboard installer — adds `cca` and `ccm` to zsh. Safe to re-run.
#
#   git clone https://github.com/aniket328/claude-switchboard ~/.local/share/claude-switchboard
#   ~/.local/share/claude-switchboard/install.sh
#
# Env: CCA_ROOT (default ~/.claude-accounts) is written into ~/.zshrc so every shell agrees on it.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
rc="${ZDOTDIR:-$HOME}/.zshrc"
root="${CCA_ROOT:-$HOME/.claude-accounts}"
mark="# >>> claude-switchboard >>>"

need() { command -v "$1" >/dev/null 2>&1 || { echo "missing: $1 — $2"; exit 1; }; }
need zsh     "cca/ccm are zsh functions"
need python3 "used for settings edits and usage checks"
command -v claude >/dev/null 2>&1 || echo "note: \`claude\` (Claude Code) not on PATH yet — cca needs it for login/status"

mkdir -p "$root" && chmod 700 "$root"
touch "$rc"
if grep -qF "$mark" "$rc"; then
  echo "already in $rc (leaving it as is)"
else
  cat >> "$rc" <<EOF

$mark
export CCA_ROOT="$root"
source "$here/cca.zsh"
# <<< claude-switchboard <<<
EOF
  echo "added to $rc"
fi

cat <<EOF

Installed. Open a new terminal (or: source $rc), then:
  cca add work && cca login work     # one profile per extra Claude login
  cca                                # list logins; * = this terminal
  cca work                           # this terminal now runs Claude Code as "work"

With claude-mem installed:
  ccm                                # which account the memory observer bills, usage, queue
  ccm patch && ccm apply             # once per claude-mem version: per-account quota state
  ccm work                           # move the observer; the queue carries on
EOF
