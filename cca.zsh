# claude-switchboard · cca — switch the Claude Code account of THIS terminal (source this; `cca` is a shell function)
#
# One CLAUDE_CONFIG_DIR per Claude login. Each profile keeps its own keychain
# credentials and refreshes them itself. Nothing copies tokens, so refresh-token
# rotation can never kill a profile. ~/.claude stays the shared base: settings,
# plugins, skills, hooks, transcripts and memory are symlinked into every profile.
#
#   cca                 list profiles (* = active in this shell)
#   cca <name>          switch this shell to <name>
#   cca base            back to ~/.claude (no CLAUDE_CONFIG_DIR)
#   cca add <name>      create profile dir, seed config, then `cca login <name>`
#   cca login [name]    browser login for the profile (once per ~30 days)
#   cca status [name]   who is logged in
#   cca rm <name>       logout + delete the profile dir
#
# cca only changes THIS terminal's login. claude-mem's observer account is global and is chosen with `ccm`
# (ccm.zsh, sourced at the end of this file).

CCA_ROOT="${CCA_ROOT:-$HOME/.claude-accounts}"   # one sub-folder per extra login
CCA_BASE="${CCA_BASE:-$HOME/.claude}"
CCA_SHARED=(settings.json settings.local.json plugins skills commands hooks agents CLAUDE.md keybindings.json projects history.jsonl chrome)

_cca_dir() { printf '%s/%s' "$CCA_ROOT" "$1"; }

_cca_email() {  # $1 = config dir or "" for base
  local out
  if ! command -v claude >/dev/null 2>&1; then   # PATH not ready (non-interactive shell): Linux file check only
    [ -f "${1:-$CCA_BASE}/.credentials.json" ] && echo "logged-in" || echo "no-login?"; return
  fi
  if [ -n "$1" ]; then out="$(CLAUDE_CONFIG_DIR="$1" claude auth status 2>/dev/null)"
  else out="$(env -u CLAUDE_CONFIG_DIR claude auth status 2>/dev/null)"; fi
  printf '%s' "$out" | python3 -c 'import json,sys
try: d=json.load(sys.stdin)
except Exception: print("?"); sys.exit()
print(d.get("email") or ("no-login" if not d.get("loggedIn") else d.get("authMethod")))'
}

_cca_seed() {  # $1 = profile dir. link shared items, seed .claude.json without identity/caches
  local d="$1" f
  mkdir -p "$d" && chmod 700 "$d"
  for f in "${CCA_SHARED[@]}"; do
    [ -e "$CCA_BASE/$f" ] || continue
    [ -e "$d/$f" ] || ln -s "$CCA_BASE/$f" "$d/$f"
  done
  if [ ! -f "$d/.claude.json" ] && [ -f "$HOME/.claude.json" ]; then python3 - "$HOME/.claude.json" "$d/.claude.json" <<'PY'
import json,sys
src,dst=sys.argv[1],sys.argv[2]
d=json.load(open(src))
drop={'userID','oauthAccount','s1mAccessCache','passesEligibilityCache','anonymousId','machineID'}
for k in list(d):
    if k in drop or k.startswith('cached') or k.endswith('Cache') or k.endswith('CacheSlots'):
        del d[k]
json.dump(d,open(dst,'w'),indent=2)
PY
  fi
  [ -f "$d/.claude.json" ] && chmod 600 "$d/.claude.json"
  return 0
}

cca() {
  local cmd="${1:-}" n d
  case "$cmd" in
  ""|list|ls)
    local active="${CLAUDE_CONFIG_DIR:-}" mark
    [ -z "$active" ] && mark='*' || mark=' '
    printf '%s %-12s %s\n' "$mark" base "$(_cca_email "")"
    for d in "$CCA_ROOT"/*/(N); do
      [ -d "$d" ] || continue
      d="${d%/}"; n="${d##*/}"
      case "$n" in *.lock) continue ;; esac   # stray "<profile>.lock/" dirs are not profiles
      [ "$active" = "$d" ] && mark='*' || mark=' '
      printf '%s %-12s %s\n' "$mark" "$n" "$(_cca_email "$d")"
    done
    ;;
  base|off)
    unset CLAUDE_CONFIG_DIR CCA_PROFILE
    echo "base (~/.claude) — $(_cca_email "")"
    ;;
  add|new)
    n="${2:?usage: cca add <name>}"; d="$(_cca_dir "$n")"
    case "$n" in base|off|list|ls|add|new|login|mem|status|current|whoami|rm|remove|help|*.lock|*/*)
      echo "reserved name: $n (base = ~/.claude; log it in with \`cca base && cca login\`)"; return 1 ;; esac
    [ -e "$d" ] && { echo "exists: $d"; return 1; }
    _cca_seed "$d"
    echo "created $d — now: cca login $n"
    ;;
  login)
    n="${2:-${CCA_PROFILE:-}}"
    if [ -n "$n" ]; then
      d="$(_cca_dir "$n")"; [ -d "$d" ] || { echo "no such profile: $n (cca add $n)"; return 1; }
      cca "$n" >/dev/null || return 1
      CLAUDE_CONFIG_DIR="$d" claude auth login --claudeai
      # `claude auth login` never sets the first-run flag, so the first `claude` in a fresh profile shows the
      # welcome/login-method screen even though the profile is logged in. Mark onboarding done.
      python3 -c 'import json,os,sys
f=os.path.join(sys.argv[1],".claude.json"); d=json.load(open(f)) if os.path.exists(f) else {}
d["hasCompletedOnboarding"]=True; d.setdefault("theme","dark"); json.dump(d,open(f,"w"),indent=2); os.chmod(f,0o600)' "$d"
    else
      env -u CLAUDE_CONFIG_DIR claude auth login --claudeai
    fi
    ;;
  mem) shift; ccm "$@" ;;   # claude-mem's account is chosen separately: see ccm.zsh
  status|current|whoami)
    n="${2:-${CCA_PROFILE:-}}"
    if [ -n "$n" ]; then d="$(_cca_dir "$n")"; echo "$n — $(_cca_email "$d")"
    else echo "base — $(_cca_email "")"; fi
    ;;
  rm|remove)
    n="${2:?usage: cca rm <name>}"; d="$(_cca_dir "$n")"
    [ -d "$d" ] || { echo "no such profile: $n"; return 1; }
    CLAUDE_CONFIG_DIR="$d" claude auth logout >/dev/null 2>&1 || true
    rm -rf "$d"
    grep -qF "\"$d\"" "${CLAUDE_MEM_DATA_DIR:-$HOME/.claude-mem}/settings.json" 2>/dev/null && echo "claude-mem still bills $n — pick another: ccm <name>"
    [ "${CLAUDE_CONFIG_DIR:-}" = "$d" ] && unset CLAUDE_CONFIG_DIR CCA_PROFILE
    echo "removed $n"
    ;;
  help|-h|--help)
    cat <<'EOF'
cca                 list profiles (* = active in this shell)
cca <name>          switch this shell to <name>
cca base            back to ~/.claude (no CLAUDE_CONFIG_DIR)
cca add <name>      create profile dir, seed config, then `cca login <name>`
cca login [name]    browser login for the profile (once per ~30 days)
cca status [name]   who is logged in
cca rm <name>       logout + delete the profile dir
EOF
    ;;
  *)
    n="$cmd"; d="$(_cca_dir "$n")"
    [ -d "$d" ] || { echo "no such profile: $n (cca add $n)"; return 1; }
    export CLAUDE_CONFIG_DIR="$d" CCA_PROFILE="$n"
    echo "$n — $(_cca_email "$d")"
    ;;
  esac
}

# claude-mem observer account (global, terminal-independent)
[ -f "${${(%):-%x}:A:h}/ccm.zsh" ] && source "${${(%):-%x}:A:h}/ccm.zsh"
