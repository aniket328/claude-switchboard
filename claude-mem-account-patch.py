#!/usr/bin/env python3
"""Make claude-mem's quota guard per-account, so `ccm <profile>` can move the observer without a restart.

claude-mem (13.28) keeps two pieces of quota state in the worker's RAM, both keyed without the account:
  - RateLimitStore ($M / zg): readings keyed by window only. A >=93% `seven_day` reading from one profile
    aborts every later spawn on every profile until that reading's resetsAt.
  - the provider cooldown latch (Da): keyed by provider ("claude"), so an exhausted profile's latch blocks
    a healthy one for 30 min, and the re-probe then trips on the stale reading above, forever.
The observation queue is RAM-only by design (SessionMessageBuffer.ts), so a restart to clear this loses it.

The patch tags each reading and each claude latch with the profile that produced it (K0e(), the basename of
CLAUDE_MEM_CLAUDE_CONFIG_DIR, read from settings.json per call) and ignores / drops state from any other
profile. Switching the setting therefore resumes the in-RAM queue on the new account at the next enqueue.
Upstream source: src/services/worker/RateLimitStore.ts and the cooldown module. Patched code loads at the
next worker start (`ccm apply` restarts only once the queue is empty).

  claude-mem-account-patch.py            patch the newest installed version (idempotent), print status
  claude-mem-account-patch.py --check    exit 0 if the newest installed version is patched
  claude-mem-account-patch.py --revert   restore the .orig backups
"""
import glob, os, shutil, subprocess, sys

MARK = '/*cwi-ccm-per-account-quota*/'
EDITS = [  # (unique original, replacement)
    ('this.entries.set(r,{...e,observedAt:Date.now()})',
     'this.entries.set(r,{...e,observedAt:Date.now(),profile:K0e()})'),
    ('let i=e.get(s);if(!i)continue;',
     'let i=e.get(s);if(!i||i.profile&&i.profile!==K0e())continue;'),
    ('let s={provider:t,message:e,...r?{window:r}:{},armedAtMs:n,',
     'let s={provider:t,message:e,...r?{window:r}:{},profile:t==="claude"?K0e():void 0,armedAtMs:n,'),
    ('let n=Da.get(t);if(!n)return{admitted:!0,claimId:null};',
     'let n=Da.get(t);if(n&&t==="claude"&&n.profile!==K0e())hee(t),n=null;if(!n)return{admitted:!0,claimId:null};'),
    ('...n.window?{window:n.window}:{},armedAtMs:n.armedAtMs}))',
     '...n.window?{window:n.window}:{},...n.profile?{profile:n.profile}:{},armedAtMs:n.armedAtMs}))'),
    ('armedAtMs:r.armedAtMs,probeInFlightSinceMs:null',
     'profile:r.profile,armedAtMs:r.armedAtMs,probeInFlightSinceMs:null'),
]

def bundles():
    root = os.path.expanduser('~/.claude/plugins/cache/thedotmack/claude-mem')
    key = lambda p: [int(x) if x.isdigit() else 0 for x in os.path.basename(os.path.dirname(os.path.dirname(p))).split('.')]
    return sorted(glob.glob(os.path.join(root, '*', 'scripts', 'worker-service.cjs')), key=key)

def patch(path):
    s = open(path, encoding='utf-8').read()
    if MARK in s: return 'already patched'
    missing = [o for o, _ in EDITS if s.count(o) != 1]
    if missing: return f'SKIPPED — {len(missing)} anchor(s) not found once (new claude-mem build; update EDITS): {missing[0][:60]}'
    for o, n in EDITS: s = s.replace(o, n, 1)
    s = s.replace('\n', '\n' + MARK + '\n', 1) if s.startswith('#!') else MARK + '\n' + s
    if not os.path.exists(path + '.orig'): shutil.copy2(path, path + '.orig')
    tmp = path[:-4] + '.ccm.cjs'; open(tmp, 'w', encoding='utf-8').write(s)
    r = subprocess.run(['node', '--check', tmp], capture_output=True, text=True)
    if r.returncode: os.remove(tmp); return 'FAILED syntax check, left untouched: ' + r.stderr[:200]
    shutil.copymode(path, tmp); os.replace(tmp, path)
    return 'patched'

if __name__ == '__main__':
    files = bundles()
    if not files: print('claude-mem not installed'); sys.exit(1)
    if '--check' in sys.argv:
        sys.exit(0 if MARK in open(files[-1], encoding='utf-8').read() else 1)
    if '--revert' in sys.argv:
        for f in files:
            if os.path.exists(f + '.orig'): os.replace(f + '.orig', f); print(f.split('/')[-3], 'reverted')
        sys.exit()
    print(files[-1].split('/')[-3], patch(files[-1]))   # only the version hooks actually run
