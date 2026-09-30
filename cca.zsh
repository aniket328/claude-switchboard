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
#   cca move <session> <name>   hand one conversation (background or ended) to another login; alias `cca switch`
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

# ── cca move: hand one conversation to another login ─────────────────────────────────────────────
# Transcripts live in the shared ~/.claude/projects, so any login can resume any session on this machine.
# A *background* session is owned by the daemon of the login that started it, so moving it = stop it there,
# then `claude --bg --resume <id>` under the new login in the same folder, same name, same permission mode.
# The conversation and its session id carry over; a workflow it was running is resumed with resumeFromRunId.
# Never attach the old entry again afterwards: that forks the conversation.

_cca_find_session() {  # $1 = id or prefix → one JSON line describing it, or exit 1
  python3 - "$1" "$CCA_ROOT" "$CCA_BASE" <<'PY'
import glob,json,os,subprocess,sys
q,root,base=sys.argv[1].lower(),sys.argv[2],sys.argv[3].rstrip('/')
profiles=[('base',base)]+[(os.path.basename(p),p) for p in sorted(glob.glob(os.path.join(root,'*'))) if os.path.isdir(p) and not p.endswith('.lock')]
hits=[]
for name,d in profiles:
    env=dict(os.environ); env.pop('CLAUDE_CONFIG_DIR',None)
    if name!='base': env['CLAUDE_CONFIG_DIR']=d
    try: out=subprocess.run(['claude','agents','--json','--all'],env=env,capture_output=True,text=True,timeout=40).stdout
    except Exception: continue
    try: items=json.loads(out)
    except Exception: continue
    for a in items if isinstance(items,list) else []:
        sid=(a.get('sessionId') or '').lower(); sh=(a.get('id') or '').lower()
        if q and (sid.startswith(q) or sh.startswith(q)):
            hits.append({'from':name,'from_dir':d,'kind':a.get('kind'),'id':a.get('id'),'sessionId':a.get('sessionId'),
                         'name':a.get('name'),'cwd':a.get('cwd'),'state':a.get('state'),'status':a.get('status'),'pid':a.get('pid')})
live=[h for h in hits if h.get('pid')] or hits
t=None
if live: h=live[0]
else:
    h={'from':None,'kind':'transcript-only'}
fs=glob.glob(os.path.join(base,'projects','*',(h.get('sessionId') or q)+'*.jsonl'))
fs=[f for f in fs if '/subagents/' not in f]
if not fs and not live: sys.exit(1)
if fs:
    t=max(fs,key=os.path.getmtime); h['transcript']=t
    h.setdefault('sessionId',os.path.basename(t)[:-6]); h['sessionId']=h.get('sessionId') or os.path.basename(t)[:-6]
    mode=cwd=None
    with open(t,'rb') as f:                               # last cwd / permission mode recorded in the transcript
        f.seek(max(0,os.path.getsize(t)-4_000_000)); tail=f.read().decode('utf-8','ignore').splitlines()
    for line in reversed(tail):
        if mode and cwd: break
        try: j=json.loads(line)
        except Exception: continue
        mode=mode or j.get('permissionMode'); cwd=cwd or j.get('cwd')
    h['mode']=mode; h['cwd']=h.get('cwd') or cwd
h['matches']=len({x['sessionId'] for x in hits}) if hits else 1
print(json.dumps(h))
PY
}

_cca_trust() {  # $1 = folder, $2 = target config dir (or "" for base), $3 = source config dir (or "" for base)
  # `claude --bg` refuses untrusted folders, and trust lives per login in <dir>/.claude.json (base: ~/.claude.json).
  # Copy the source login's trust for this folder to the target. Exit 2 if the source never trusted it.
  python3 - "$1" "$2" "$3" <<'PY'
import json,os,sys
cwd,to,frm=sys.argv[1:4]
cfg=lambda d: os.path.join(d,'.claude.json') if d else os.path.expanduser('~/.claude.json')
def load(p):
    try: return json.load(open(p))
    except Exception: return {}
src=load(cfg(frm)).get('projects',{}).get(cwd,{})
t=load(cfg(to)); pr=t.setdefault('projects',{}).setdefault(cwd,{})
if pr.get('hasTrustDialogAccepted'): sys.exit(0)
if not src.get('hasTrustDialogAccepted'): sys.exit(2)
pr['hasTrustDialogAccepted']=True
tmp=cfg(to)+'.cca'; json.dump(t,open(tmp,'w'),indent=2); os.chmod(tmp,0o600); os.replace(tmp,cfg(to)); print('trusted')
PY
}

_cca_move() {  # $1 = session id/prefix, $2 = target login; --yes skips prompts, --note "…" replaces the hand-off message
  local sid="$1" to="$2" yes=0 note="" info from from_dir cwd name mode pid kind full out ans i todir fromproj toproj u
  shift 2 2>/dev/null
  while [ $# -gt 0 ]; do case "$1" in --yes|-y) yes=1 ;; --note) note="$2"; shift ;; esac; shift; done
  [ -n "$sid" ] && [ -n "$to" ] || { echo "usage: cca move <session-id> <login> [--yes] [--note \"…\"]"; return 1; }
  if [ "$to" = base ]; then todir="$CCA_BASE"; else todir="$(_cca_dir "$to")"; fi
  [ -d "$todir" ] || { echo "no such login: $to (cca add $to)"; return 1; }
  case "$(_cca_email "$([ "$to" = base ] || echo "$todir")")" in no-login*|\?) echo "$to is not logged in — cca login $to"; return 1 ;; esac

  echo "looking for $sid in every login…"
  info="$(_cca_find_session "$sid")" || { echo "no session or transcript matches $sid"; return 1; }
  eval "$(python3 -c 'import json,shlex,sys
h=json.loads(sys.argv[1])
for k in ("from","from_dir","cwd","name","mode","pid","kind","sessionId","matches"):
    print("_m_%s=%s" % (k, shlex.quote(str(h.get(k) or ""))))' "$info")"
  from="$_m_from" from_dir="$_m_from_dir" cwd="$_m_cwd" name="$_m_name" mode="${_m_mode:-default}" pid="$_m_pid" kind="$_m_kind" full="$_m_sessionId"
  [ "${_m_matches:-1}" -gt 1 ] && { echo "$sid matches more than one session — give more characters"; return 1; }
  [ -n "$cwd" ] && [ -d "$cwd" ] || { echo "session folder not found on this machine: ${cwd:-?}"; return 1; }
  [ "$from" = "$to" ] && { echo "$full already runs under $to"; return 0; }

  fromproj="$(cd "${from_dir:-$CCA_BASE}/projects" 2>/dev/null && pwd -P)"; toproj="$(cd "$todir/projects" 2>/dev/null && pwd -P)"
  [ -n "$toproj" ] && [ "$toproj" = "$(cd "$CCA_BASE/projects" && pwd -P)" ] \
    || { echo "$to does not share ~/.claude/projects (its transcripts are separate) — relink it first"; return 1; }

  echo "session  ${name:-(unnamed)}  $full"
  echo "folder   $cwd   · mode $mode"
  echo "from     ${from:-no background owner (interactive or ended)}${pid:+ · running pid $pid}"
  echo "to       $to — $(_cca_email "$([ "$to" = base ] || echo "$todir")")"
  if typeset -f _ccm_py >/dev/null; then
    u="$(_ccm_py usage "$todir")"; echo "         ${u#* }"
    [ "${u%% *}" = ok ] || { [ $yes = 1 ] || { printf '%s is short on quota. Move anyway? [y/N] ' "$to"; read -r ans; [[ $ans == [yY] ]] || return 1; }; }
  fi
  if [ "$kind" = interactive ] && [ -n "$pid" ]; then
    echo "it is open in an interactive terminal — /exit it there first, then re-run"; return 1
  fi
  [ $yes = 1 ] || { printf 'Stop it under %s and resume under %s? [y/N] ' "${from:-—}" "$to"; read -r ans; [[ $ans == [yY] ]] || { echo "unchanged"; return 1; }; }

  if [ -n "$from" ] && [ -n "$pid" ]; then
    if [ "$from" = base ]; then env -u CLAUDE_CONFIG_DIR claude stop "${full:0:8}" >/dev/null 2>&1
    else CLAUDE_CONFIG_DIR="$from_dir" claude stop "${full:0:8}" >/dev/null 2>&1; fi
    for i in {1..40}; do kill -0 "$pid" 2>/dev/null || break; sleep 0.5; done
    kill -0 "$pid" 2>/dev/null && { echo "could not stop pid $pid under $from — nothing was moved"; return 1; }
    echo "stopped under $from"
  fi

  _cca_trust "$cwd" "$([ "$to" = base ] || echo "$todir")" "$([ "${from:-base}" = base ] || echo "$from_dir")"
  case $? in 0) ;; 2) echo "$to has not trusted $cwd and neither had ${from:-the old login} — run \`claude\` there once under $to"; return 1 ;; *) echo "could not update $to's trust list"; return 1 ;; esac
  [ -n "$note" ] || note="[cca move] This session was moved from the ${from:-previous} Claude account to the $to account (same conversation, same folder). Carry on exactly where you left off. If a workflow was running, resume it with resumeFromRunId; if the last turn was cut off by a usage limit, redo that step."
  out="$(cd "$cwd" && if [ "$to" = base ]; then env -u CLAUDE_CONFIG_DIR claude --bg --resume "$full" --name "${name:-moved ${full:0:8}}" --permission-mode "$mode" "$note"
         else CLAUDE_CONFIG_DIR="$todir" claude --bg --resume "$full" --name "${name:-moved ${full:0:8}}" --permission-mode "$mode" "$note"; fi 2>&1)"
  echo "$out" | tail -3
  for i in {1..30}; do
    if (if [ "$to" = base ]; then env -u CLAUDE_CONFIG_DIR claude agents --json; else CLAUDE_CONFIG_DIR="$todir" claude agents --json; fi) 2>/dev/null | grep -q "\"$full\""; then
      echo "moved: ${full:0:8} now runs under $to.  Watch: CLAUDE_CONFIG_DIR=$todir claude attach ${full:0:8}"
      [ -n "$from" ] && echo "do NOT attach it under $from again — that would fork the conversation"
      return 0
    fi
    sleep 1
  done
  echo "resume command ran but the session is not listed under $to yet — check: cca $to && claude agents"; return 1
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
    case "$n" in base|off|list|ls|add|new|login|mem|move|switch|status|current|whoami|rm|remove|help|*.lock|*/*)
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
  move|switch) shift; _cca_move "$@" ;;
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
cca move <session> <name> [--yes] [--note "…"]
                    hand one conversation to another login: stop it under its current login, resume the same
                    session id under <name> in the same folder (alias: cca switch)
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
