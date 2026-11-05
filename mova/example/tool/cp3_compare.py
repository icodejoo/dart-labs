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
    # newFail 是状态变化，不等于产品回归；旧 BLOCKED 首次失败单独列出。
    first_observed = sorted(k for k in new_fail if old.get(k, {}).get('status') == 'BLOCKED')
    categories = {'产品缺陷': [], '夹具缺陷': [], '旧基线无证据': []}
    for k in new_fail:
        category = new[k].get('triageCategory')
        if category in categories:
            categories[category].append(k)
        elif k in first_observed:
            categories['旧基线无证据'].append(k)
    integrity = current.get('evidenceErrors', []) if isinstance(current, dict) else []
    # 所有 FAIL、缺行及完整性错误继续阻止验收通过。
    return dict(passed=not (new_fail or new_blocked or missing or integrity), newFail=new_fail,
                firstObservedFail=first_observed,
                regressions=sorted(k for k in new_fail if old.get(k, {}).get('status') == 'PASS'),
                failCategories=categories, evidenceErrors=integrity,
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
