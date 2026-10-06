"""SAO Browser Lease and Owner Takeover Broker for musebrowser.

Provides safe human-agent coexistence:
- Owner takeover: Stop (/owner/stop) immediately revokes leases and pauses agents.
- Owner resume: Resume (/owner/resume) re-enables agent operations.
- Leases: Agents acquire 60-second renewable leases (max 5-minute total turn).
- FIFO queue: Waiting agents queue up to 50 entries with 30s liveness sweeps.
- Input gating: All mutating actions are rejected if owner has paused or another action is active.
"""

import json
import os
from pathlib import Path
import secrets
import threading
import time


class BrokerError(Exception):
    pass


class Broker:
    def __init__(self, state_file=None, clock=time.monotonic):
        self.clock = clock
        self.state_file = Path(state_file) if state_file else None
        self.lock = threading.RLock()
        self.lease = None
        self.queue = []
        self.busy = False
        self.paused = False
        self.last_action = None

        if self.state_file and self.state_file.exists():
            try:
                saved = json.loads(self.state_file.read_text())
                self.paused = bool(saved.get('paused', False))
            except Exception:
                pass

    def save(self):
        if self.state_file:
            try:
                self.state_file.parent.mkdir(parents=True, exist_ok=True)
                temp = self.state_file.with_suffix('.tmp')
                temp.write_text(json.dumps({'paused': self.paused, 'busy': self.busy}))
                temp.replace(self.state_file)
            except Exception:
                pass

    def sweep(self):
        now = self.clock()
        self.queue = [item for item in self.queue if now - item.get('seen', 0) < 30]
        if self.lease and now >= self.lease.get('expires', 0):
            self.lease = None

    def status(self):
        with self.lock:
            self.sweep()
            return {
                'name': 'SAO MuseBrowser',
                'paused': self.paused,
                'busy': self.busy,
                'holder': self.lease['label'] if self.lease else None,
                'remainingSeconds': max(0, round(self.lease['expires'] - self.clock())) if self.lease else 0,
                'queue': [item['label'] for item in self.queue],
                'lastAction': self.last_action
            }

    def acquire(self, caller, label, request_id):
        if not all(isinstance(v, str) and 1 <= len(v) <= 180 for v in (caller, label, request_id)):
            raise BrokerError('Invalid caller, label, or request identity')
        with self.lock:
            self.sweep()
            if self.paused:
                return {'status': 'paused'}
            if self.lease and self.lease['caller'] == caller and self.lease['request'] == request_id:
                return {'status': 'acquired', 'lease': self.lease['token']}
            entry = next((item for item in self.queue if item['request'] == request_id and item['caller'] == caller), None)
            if entry:
                entry['seen'] = self.clock()
            else:
                if len(self.queue) >= 50:
                    raise BrokerError('Browser queue is full')
                self.queue.append({'caller': caller, 'label': label, 'request': request_id, 'seen': self.clock()})

            first = self.queue[0]
            if not self.lease and not self.busy and first['request'] == request_id and first['caller'] == caller:
                self.queue.pop(0)
                self.lease = {
                    **first,
                    'token': secrets.token_urlsafe(32),
                    'expires': self.clock() + 60,
                    'started': self.clock()
                }
                return {'status': 'acquired', 'lease': self.lease['token']}
            pos = next((i + 1 for i, item in enumerate(self.queue) if item['request'] == request_id and item['caller'] == caller), 1)
            return {'status': 'queued', 'position': pos}

    def validate(self, caller, token):
        self.sweep()
        if self.paused:
            raise BrokerError('Browser paused by owner')
        if not self.lease:
            raise BrokerError('No active browser lease')
        if self.lease['caller'] != caller or not secrets.compare_digest(self.lease['token'], str(token)):
            raise BrokerError('Browser lease expired, invalid, or released')

    def release(self, caller, token=None, request_id=None):
        with self.lock:
            self.queue = [item for item in self.queue if not (item['caller'] == caller and item['request'] == request_id)]
            if self.lease and self.lease['caller'] == caller and (not token or secrets.compare_digest(self.lease['token'], str(token))):
                self.lease = None
            return {'released': True}

    def owner(self, pause):
        with self.lock:
            if not pause and self.busy:
                raise BrokerError('The last action is still finishing; retry resume when idle')
            self.paused = bool(pause)
            self.lease = None
            self.queue = []
            self.save()
            return self.status()

    def start_action(self, caller=None, token=None, op_name='action'):
        with self.lock:
            if caller is not None or token is not None:
                self.validate(caller, token)
                if self.clock() - self.lease['started'] >= 300:
                    self.lease = None
                    raise BrokerError('Five-minute browser turn finished; release and queue again')
                self.lease['expires'] = self.clock() + 60
            elif self.paused:
                raise BrokerError('Browser paused by owner')

            if self.busy:
                raise BrokerError('An action is already in flight')
            self.busy = True
            self.save()

    def finish_action(self, op_name='action', outcome='ok'):
        with self.lock:
            self.busy = False
            self.last_action = {'name': op_name, 'outcome': outcome}
            self.save()
