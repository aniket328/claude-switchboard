#!/usr/bin/env python3
"""Stand-in for Anthropic's OAuth usage endpoint and a claude-mem worker, for the demo and smoke tests.
Sample numbers only. Behaves like a patched worker: a pause armed by one account is ignored once
claude-mem bills another, and the queue then drains."""
import json, os, sys, time
from http.server import BaseHTTPRequestHandler, HTTPServer

DATA = os.environ['CLAUDE_MEM_DATA_DIR']; BUNDLE = os.environ['DEMO_BUNDLE']; T0 = time.time()
USAGE = {'default': (42, 10), 'work': (96, 41), 'personal': (18, 6), 'client-acme': (55, 12)}
state = {'queue': 2941}

def billed():
    d = json.load(open(os.path.join(DATA, 'settings.json'))).get('CLAUDE_MEM_CLAUDE_CONFIG_DIR', '')
    return 'default' if d.rstrip('/').endswith('/.claude') else os.path.basename(d.rstrip('/'))

def pause():
    p = os.path.join(DATA, 'quota-cooldown.json')
    try: c = json.load(open(p))[0]
    except Exception: return None
    if c.get('profile') != billed(): os.remove(p); return None     # patched worker: foreign pause dropped
    return c

class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def send(self, obj):
        b = json.dumps(obj).encode(); self.send_response(200)
        self.send_header('content-type', 'application/json'); self.send_header('content-length', str(len(b)))
        self.end_headers(); self.wfile.write(b)
    def do_GET(self):
        if self.path.startswith('/api/oauth/usage'):
            who = self.headers.get('Authorization', '').split()[-1]
            s, f = USAGE.get(who, (None, None))
            return self.send({'seven_day': {'utilization': s}, 'five_hour': {'utilization': f}})
        c = pause()
        if self.path == '/api/processing-status':
            state['queue'] = state['queue'] + 3 if c else max(0, state['queue'] - 1180)
            return self.send({'isProcessing': state['queue'] > 0, 'queueDepth': state['queue'], 'parkedSessions': 0})
        if self.path == '/api/health':
            rl = {'seven_day': {'utilization': .96, 'resetsAt': int(time.time()) + 172800, 'observedAt': int(T0 * 1000),
                                'profile': 'work', 'rateLimitType': 'seven_day'}} if c else {}
            return self.send({'status': 'ok', 'pid': 4242, 'uptime': int(time.time() - T0), 'workerPath': BUNDLE,
                              'ai': {'authMethod': f'Claude Code OAuth token profile={billed()}'}, 'rateLimits': rl})
        self.send_response(404); self.end_headers()

HTTPServer(('127.0.0.1', int(sys.argv[1])), H).serve_forever()
