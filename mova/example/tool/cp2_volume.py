"""Bounded system-volume sampling; imports and unit tests never contact a device."""
import json
import queue
import re
import threading
import time


def sample_volume(marker, read, *, received=None, now=time.monotonic, pause=time.sleep):
    received = now() if received is None else received
    attempts = []
    for attempt in range(3):
        if now() - received > 3:
            break
        try:
            raw = read()
            valid = re.search(r'volume is (\d+)', raw) is not None
            attempts.append(dict(raw=raw, valid=valid))
            if valid and now() - received <= 3:
                return dict(marker=marker, raw=raw, status='OK', attempts=attempts,
                            elapsedMs=round((now()-received)*1000))
        except Exception as error:
            attempts.append(dict(error=repr(error)))
        if attempt < 2:
            pause(.1)
    return dict(marker=marker, raw='', status='BLOCKED', attempts=attempts,
                reason='system volume unavailable within 3s; no retrospective sample',
                elapsedMs=round((now()-received)*1000))


class VolumeSampler:
    """Keep adb retries off the log reader and persist every completed request."""
    def __init__(self, path, read):
        self.path, self.read, self.rows = path, read, []
        self.pending = queue.Queue()
        self.worker = threading.Thread(target=self._run, daemon=True)
        self.worker.start()

    def submit(self, marker):
        self.pending.put((marker, time.monotonic()))

    def flush(self):
        self.pending.join()

    def _run(self):
        while True:
            item = self.pending.get()
            try:
                if item is None:
                    return
                marker, received = item
                self.rows.append(sample_volume(marker, self.read, received=received))
                self.path.write_text(json.dumps(self.rows, ensure_ascii=False), encoding='utf-8')
            finally:
                self.pending.task_done()

    def close(self):
        self.pending.put(None)
        self.worker.join(timeout=15)
        if self.worker.is_alive():
            raise RuntimeError('BLOCKED: system volume sampler did not drain')


def volume_proof(rows, variants, runs):
    expected = ['before'] + [f'verdict:{v}:{i}' for v in variants for i in range(runs)] + ['after']
    missing = [m for m in expected if sum(r.get('marker') == m and
        r.get('status') == 'OK' and re.search(r'volume is (\d+)', r.get('raw', '')) is not None
        for r in rows) != 1]
    invalid = [r.get('marker', '<unidentified>') for r in rows if
        r.get('status') != 'OK' or re.search(r'volume is (\d+)', r.get('raw', '')) is None]
    invalid += [r['marker'] for r in rows if str(r.get('marker', '')).startswith('verdict:')
                and r['marker'] not in expected]
    if missing or invalid:
        return 'BLOCKED', dict(expected=len(expected), missing=missing, invalid=invalid,
            reason='incomplete system volume proof; missing/stale/failed samples are BLOCKED')
    values = {re.search(r'volume is (\d+)', r['raw'])[1] for r in rows}
    return ('PASS' if len(values) == 1 else 'FAIL'), dict(expected=len(expected),
        missing=[], invalid=[], values=sorted(values), reason='system volume must remain unchanged')
