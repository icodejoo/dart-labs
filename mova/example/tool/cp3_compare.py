"""Offline CP3 gate: exact IDs, missing rows block, no new FAIL/BLOCKED."""
import argparse
import json
from pathlib import Path

STATUSES = {'PASS', 'FAIL', 'BLOCKED'}

def read_rows(data):
    rows = data.get('rows') if isinstance(data, dict) else data
    if not isinstance(rows, list) or not rows:
        raise ValueError('expected non-empty ledger rows')
    result = {}
    for raw in rows:
        row = raw if isinstance(raw, dict) else dict(zip(('id', 'status', 'evidence'), raw))
        ident, status = row.get('id'), row.get('status')
        if not isinstance(ident, str) or not ident or ident in result or status not in STATUSES:
            raise ValueError('duplicate ID / invalid ID or status')
        result[ident] = row
    return result

def compare(baseline, current):
    old, new = read_rows(baseline), read_rows(current)
    missing = sorted(old.keys() - new.keys())
    new_fail = sorted(k for k, r in new.items() if r['status'] == 'FAIL' and old.get(k, {}).get('status') != 'FAIL')
    new_blocked = sorted(set(missing) | {k for k, r in new.items() if r['status'] == 'BLOCKED' and old.get(k, {}).get('status') != 'BLOCKED'})
    # Missing rows are always a coverage error, including old BLOCKED rows.
    return dict(passed=not (new_fail or new_blocked or missing), newFail=new_fail,
                newBlocked=new_blocked, missing=missing,
                retainedBlocked=sorted(k for k, r in new.items() if r['status'] == 'BLOCKED' and old.get(k, {}).get('status') == 'BLOCKED'))

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('cp0', type=Path)
    p.add_argument('current', type=Path)
    p.add_argument('--output', type=Path)
    a = p.parse_args()
    try:
        result = compare(json.loads(a.cp0.read_text(encoding='utf-8')), json.loads(a.current.read_text(encoding='utf-8')))
    except (OSError, ValueError, TypeError) as error:
        p.error(str(error))
    text = json.dumps(result, ensure_ascii=False, indent=2)
    print(text)
    if a.output:
        a.output.write_text(text + '\n', encoding='utf-8')
    return 0 if result['passed'] else 1

if __name__ == '__main__':
    raise SystemExit(main())
