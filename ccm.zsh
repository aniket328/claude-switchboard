# claude-switchboard · ccm — which Claude account the claude-mem observer bills (sourced by cca.zsh)
#
# `cca` switches THIS terminal's login. `ccm` switches the ONE global claude-mem worker's observer account,
# for every terminal at once. They are independent: switching terminals never moves claude-mem.
#
#   ccm                 status: account in use, usage per account, queue, pause, patch loaded?
#   ccm <name> | base   bill that account from the next observer spawn; queued observations carry on
#   ccm auto            bill the account with the most weekly headroom
#   ccm apply           load the per-account patch into the running worker: waits until the queue is empty,
#                       then restarts it (lossless). Needed once per claude-mem version.
#   ccm patch           re-patch after a claude-mem update (then `ccm apply`)
#   ccm restart         restart now even with a queue (asks; the queue is lost)
#
# Why a patch: stock claude-mem 13.28 keys its quota pause and rate-limit readings by provider/window, not by
# account, so one exhausted account keeps every account paused and only a restart (which drops the RAM-only
# queue) clears it. claude-mem-account-patch.py ties both to the account, so `ccm <other>` resumes at once.
# Details: README.md in https://github.com/aniket328/claude-switchboard

CCM_TOOLS="${${(%):-%x}:A:h}"
CCM_DATA="${CLAUDE_MEM_DATA_DIR:-$HOME/.claude-mem}"

_ccm_py() {  # $1 = status | usage <dir> | set <dir> | auto | queue | loaded | pid | dir <name>
  [ -f "$CCM_DATA/settings.json" ] || { echo "claude-mem not installed ($CCM_DATA/settings.json missing)"; return 1; }
  python3 - "$CCA_ROOT" "$CCA_BASE" "$CCM_DATA" "$@" <<'PY'
import glob,hashlib,json,os,platform,subprocess,sys,time,urllib.request
root,base,data,mode=sys.argv[1:5]; arg=sys.argv[5] if len(sys.argv)>5 else ''
SEVEN,FIVE=85,90                                   # headroom rule, below claude-mem's own 93% / 95% stop
MARK='/*cwi-ccm-per-account-quota*/'
base=base.rstrip('/'); sp=os.path.join(data,'settings.json')
def nm(d): d=(d or base).rstrip('/'); return 'base' if d==base else os.path.basename(d)
def profiles():
    ps=[base]
    for n in sorted(os.listdir(root)) if os.path.isdir(root) else []:
        p=os.path.join(root,n)
        if os.path.isdir(p) and not n.endswith('.lock'): ps.append(p)
    return ps
def token(d):
    if platform.system()=='Darwin':                 # claude-mem's own service name: sha256(dir)[:8], none for ~/.claude
        svc='Claude Code-credentials'+('' if d==base else '-'+hashlib.sha256(d.encode()).hexdigest()[:8])
        raw=subprocess.run(['security','find-generic-password','-s',svc,'-w'],capture_output=True,text=True,timeout=5).stdout
    else: raw=open(os.path.join(d,'.credentials.json')).read()
    return json.loads(raw)['claudeAiOauth']['accessToken']
def usage(d):                                        # (7-day %, 5-hour %), (None,None) if not logged in / token stale
    try:
        r=urllib.request.Request(os.environ.get('CCM_USAGE_URL','https://api.anthropic.com/api/oauth/usage'),   # override: tests/demo
            headers={'Authorization':'Bearer '+token(d),'anthropic-beta':'oauth-2025-04-20'})
        j=json.load(urllib.request.urlopen(r,timeout=6))
        return (j.get('seven_day') or {}).get('utilization'),(j.get('five_hour') or {}).get('utilization')
    except Exception: return None,None
def ok(u): return u[0] is not None and u[0]<SEVEN and (u[1] or 0)<FIVE
def fmt(u): return 'unknown' if u[0] is None else f'7d {u[0]:.0f}% · 5h {u[1] or 0:.0f}%'
def worker(path):
    port=json.load(open(sp)).get('CLAUDE_MEM_WORKER_PORT') or str(37700+os.getuid()%100)
    try: return json.load(urllib.request.urlopen(f'http://127.0.0.1:{port}{path}',timeout=3))
    except Exception: return None
def bundle():
    fs=sorted(glob.glob(os.path.expanduser('~/.claude/plugins/cache/thedotmack/claude-mem/*/scripts/worker-service.cjs')),
              key=lambda p:[int(x) if x.isdigit() else 0 for x in p.split('/')[-3].split('.')])
    return fs[-1] if fs else None
def patch_state():                                   # loaded | on-disk | unpatched | down
    b=bundle(); h=worker('/api/health')
    if not b or MARK not in open(b,encoding='utf-8',errors='ignore').read(): return 'unpatched'
    if not h: return 'down'
    started=time.time()-h.get('uptime',0)
    return 'loaded' if h.get('workerPath')==b and started>os.path.getmtime(b) else 'on-disk'
def paused():
    try: return json.load(open(os.path.join(data,'quota-cooldown.json')))
    except Exception: return []
def write(d):
    s=json.load(open(sp))
    if s.get('CLAUDE_MEM_CLAUDE_CONFIG_DIR')==d: return False
    s['CLAUDE_MEM_CLAUDE_CONFIG_DIR']=d
    json.dump(s,open(sp+'.ccm','w'),indent=2); os.replace(sp+'.ccm',sp); return True
cur=(json.load(open(sp)).get('CLAUDE_MEM_CLAUDE_CONFIG_DIR') or base).rstrip('/')

if mode=='dir':
    d=base if arg=='base' else os.path.join(root,arg)
    if not os.path.isdir(d): sys.exit(1)
    print(d)
elif mode=='usage':
    u=usage(arg.rstrip('/')); print(('ok ' if ok(u) else 'low ')+fmt(u))
elif mode=='set':
    d=arg.rstrip('/'); changed=write(d)
    print(f'claude-mem → {nm(d)}' + ('' if changed else ' (already)'))
elif mode=='auto':
    best=sorted(((u[0],p,u) for p in profiles() for u in [usage(p)] if ok(u)),key=lambda x:x[0])
    if not best: print(f'no account under {SEVEN}% weekly — left on {nm(cur)}'); sys.exit(1)
    write(best[0][1]); print(f'claude-mem → {nm(best[0][1])} ({fmt(best[0][2])})')
elif mode=='queue':
    print((worker('/api/processing-status') or {}).get('queueDepth','?'))
elif mode=='loaded':
    print(patch_state())
elif mode=='pid':
    print((worker('/api/health') or {}).get('pid',''))
else:  # status
    print(f'claude-mem bills: {nm(cur)}   (ccm <name> to change; independent of cca)')
    for p in profiles(): u=usage(p); print(f"  {'>' if p==cur else ' '} {nm(p):<12} {fmt(u):<20} {'ok' if ok(u) else '—'}")
    h=worker('/api/health')
    if not h: print('worker: not running (the next Claude hook starts it)'); sys.exit()
    q=(worker('/api/processing-status') or {}).get('queueDepth','?')
    auth=h.get('ai',{}).get('authMethod',''); prof=auth.split('profile=')[-1] if 'profile=' in auth else '?'
    print(f"worker: pid {h.get('pid')} · up {h.get('uptime',0)//3600}h · queue {q} in RAM · last spawn billed {prof}")
    ps=patch_state()
    print({'loaded':'patch: LOADED — pauses and readings are per account; ccm <name> resumes the queue at once',
           'on-disk':'patch: on disk, NOT loaded in this worker — run `ccm apply` (waits for an empty queue)',
           'unpatched':'patch: MISSING for this claude-mem version — run `ccm patch`, then `ccm apply`'}.get(ps,'patch: ?'))
    for c in paused():
        who=c.get('profile') or '?'
        print(f"PAUSED since {time.strftime('%d %b %H:%M',time.localtime(c['armedAtMs']/1000))} by {who}: {c.get('message')} ({c.get('window')})"
              + (' — ignored once the worker sees another account' if ps=='loaded' and who!=nm(cur) else ', re-probed every 30 min'))
    now=time.time(); lim={'five_hour':.95,'seven_day':.93,'seven_day_opus':.93,'seven_day_sonnet':.92}
    for w,r in (h.get('rateLimits') or {}).items():
        u,t=r.get('utilization'),r.get('resetsAt') or 0
        if u is not None and w in lim and u>=lim[w] and t>now:
            print(f"blocking reading: {w} {u*100:.0f}% from {r.get('profile','an unknown account')}, until {time.strftime('%a %d %b %H:%M',time.localtime(t))}"
                  + (' (ignored for other accounts)' if ps=='loaded' else ''))
PY
}

_ccm_restart_now() {  # graceful restart via the worker's own endpoint; Linux boxes use their systemd unit
  local old new i port
  old="$(_ccm_py pid)"
  if [ "$(uname -s)" = Linux ] && systemctl --user is-active claude-mem-worker >/dev/null 2>&1; then
    systemctl --user restart claude-mem-worker
  else
    port="$(python3 -c 'import json,os,sys;print(json.load(open(sys.argv[1])).get("CLAUDE_MEM_WORKER_PORT") or 37700+os.getuid()%100)' "$CCM_DATA/settings.json")"
    curl -s -m5 -X POST "http://127.0.0.1:$port/api/admin/restart" >/dev/null
  fi
  for i in {1..40}; do sleep 1; new="$(_ccm_py pid)"; [ -n "$new" ] && [ "$new" != "$old" ] && break; done
  if [ -n "$new" ] && [ "$new" != "$old" ]; then echo "worker restarted: pid $old → $new"; return 0; fi
  echo "worker did not come back within 40 s — it starts again on the next Claude hook; check with \`ccm\`"; return 1
}

ccm() {
  local cmd="${1:-}" d u q ans last=-1 stall=0 zero=0
  case "$cmd" in
  ""|status) _ccm_py status ;;
  auto) _ccm_py auto ;;
  patch) python3 "$CCM_TOOLS/claude-mem-account-patch.py" ;;
  apply)
    python3 "$CCM_TOOLS/claude-mem-account-patch.py" || return 1
    case "$(_ccm_py loaded)" in
      loaded) echo "patch already loaded in the running worker"; return 0 ;;
      unpatched) echo "patch could not be applied to this claude-mem version — see above"; return 1 ;;
      down) echo "worker not running — the next Claude hook starts it with the patch"; return 0 ;;
    esac
    echo "Waiting for the queue to empty before restarting (Ctrl-C stops; waiting loses nothing)."
    while :; do
      q="$(_ccm_py queue)"
      [ "$q" = "?" ] && { echo "worker gone — the next hook starts it patched"; return 0; }
      if [ "$q" = 0 ]; then zero=$((zero+1)); [ $zero -ge 2 ] && break; sleep 2; continue; fi
      zero=0
      if [ "$q" -ge "$last" ] && [ "$last" -ge 0 ]; then stall=$((stall+1)); else stall=0; fi
      [ $stall = 4 ] && echo "  queue is not draining (claude-mem is paused, see \`ccm\`). Keep waiting, or \`ccm restart\` to accept losing it."
      echo "  queue $q …"; last=$q; sleep 30
    done
    _ccm_restart_now && echo "patch state: $(_ccm_py loaded)"
    ;;
  restart)
    q="$(_ccm_py queue)"
    printf 'Restart the claude-mem worker now? %s queued observations will be LOST. [y/N] ' "$q"; read -r ans
    [ "$ans" = y ] || [ "$ans" = Y ] || { echo "kept"; return 1; }
    rm -f "$CCM_DATA/quota-cooldown.json"   # else the pause is re-armed at boot
    _ccm_restart_now
    ;;
  help|-h|--help) sed -n '3,12p' "$CCM_TOOLS/ccm.zsh" | sed 's/^# \{0,1\}//' ;;
  *)
    d="$(_ccm_py dir "$cmd")" || { echo "no such account: $cmd (see \`cca\`)"; return 1; }
    u="$(_ccm_py usage "$d")"
    if [ "${u%% *}" != ok ]; then
      printf '%s is at %s — claude-mem stops at 93%% weekly. Use it anyway? [y/N] ' "$cmd" "${u#* }"; read -r ans
      [ "$ans" = y ] || [ "$ans" = Y ] || { echo "unchanged"; return 1; }
    fi
    _ccm_py set "$d"
    echo "  ${u#* }"
    case "$(_ccm_py loaded)" in
      loaded)  echo "  takes effect at the next observation; the queue carries on" ;;
      on-disk) echo "  NOTE: this worker still runs unpatched code, so an existing pause from another account stays until \`ccm apply\`" ;;
      unpatched) echo "  NOTE: claude-mem is unpatched — run \`ccm patch\` then \`ccm apply\`, or an old pause can keep blocking" ;;
    esac
    ;;
  esac
}
