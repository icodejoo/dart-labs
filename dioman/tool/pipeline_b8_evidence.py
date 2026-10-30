"""核对 B8 全量、方法矩阵与 B7 裁决，保留逐格证据。"""
from collections import Counter
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / 'docs/reports/pipeline-b8-evidence'


def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def cell(row):
    return f"{row['scenario']}|{row['network']}@{row['style']}"


def status(row):
    reasons = row.get('reasons', [])
    if any('未声明' in r or r.startswith('不适用：') for r in reasons):
        return '不适用'
    if row['status'] == '跳过' and any(r.startswith('skipped: missing') for r in reasons):
        return '缺能力'
    return row['status']


def run():
    names = ['acceptance-full.json', 'acceptance-final.json', 'plugin-matrix-final.json']
    sources = []
    latest = {}
    reports = {}
    for name in names:
        path = DEST / name
        report = reports[name] = read(path)
        assert report['planned'] == report['executed'] and not report['interrupted'], name
        assert report['executed'] == len(report['results']), name
        sources.append(dict(path=str(path.relative_to(ROOT)),
                            sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
                            bytes=path.stat().st_size, planned=report['planned'],
                            executed=report['executed'], interrupted=report['interrupted'],
                            counts=dict(Counter(r['status'] for r in report['results']))))
        for row in report['results']:
            latest[cell(row)] = row
    assert reports['acceptance-final.json']['planned'] == 6426
    final_rows = reports['acceptance-final.json']['results']
    assert len({cell(r) for r in final_rows}) == 6426
    assert len({r['scenario'] for r in final_rows}) == 459
    counts = Counter(status(r) for r in latest.values())
    assert counts['失败'] == 0 and len(latest) == 6426
    initial = reports['acceptance-full.json']['results']
    failures = [dict(cell=cell(r), before=r['reasons'], after=status(latest[cell(r)]))
                for r in initial if r['status'] == '失败']
    assert all(r['after'] == '通过' for r in failures)
    old = read(DEST / 'b7-summary.json')['cases']
    old_na = {f'{scene}|{dim}' for scene, values in old.items()
              for dim, value in values.items() if value == '不适用'}
    new_na = {key for key, row in latest.items() if status(row) == '不适用'}
    added = sorted(new_na - old_na)
    assert not added, added
    decisions = []
    for filename in ['applicability-reconciliation.json', 'notify-applicability-reconciliation.json']:
        old_decisions = read(ROOT / 'docs/reports/pipeline-b7-evidence' / filename)
        for entry in old_decisions['entries']:
            after = latest[entry['cell']]
            decisions.append(dict(cell=entry['cell'], before='不适用',
                                  rule_before_failure=entry['before'], reason=entry['reason'],
                                  after=status(after), reasons=after.get('reasons', [])))
    transitions = Counter(r['after'] for r in decisions)
    assert transitions == {'通过': 39, '缺能力': 2, '不适用': 2}, transitions
    (DEST / 'applicability-reconciliation.json').write_text(json.dumps(dict(
        decisions=decisions, transitions=dict(transitions), new_not_applicable=added,
        removed_not_applicable=sorted(old_na - new_na), initial_failures=failures),
        ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    executed = [r for r in latest.values() if r['status'] == '通过']
    for r in executed:
        assert r['events']['pending_after'] == 0, cell(r)
        assert r['events']['active_cancel_tokens'] == 0, cell(r)
        assert r['server']['inflight'] == 0, cell(r)
        loading = r['events']['loading']
        assert len(loading) % 2 == 0, cell(r)
        assert loading == [i % 2 == 0 for i in range(len(loading))], cell(r)
    methods = reports['plugin-matrix-final.json']['results']
    method_counts = {}
    for row in methods:
        method_counts.setdefault(row['method'], Counter())[status(row)] += 1
    proxy_ids = {r['proxyId'] for report in reports.values() for r in report['results'] if r.get('proxyId')}
    summary = dict(sources=sources, unique_cells=len(latest), counts=dict(counts),
                   skip_reasons=dict(Counter(reason for r in latest.values()
                                             if r['status'] == '跳过' for reason in r.get('reasons', []))),
                   invariants=dict(checked=len(executed), pending_after=0,
                                   active_cancel_tokens=0, inflight=0, loading_paired=True),
                   method_matrix={k: dict(v) for k, v in method_counts.items()},
                   b7_counts=dict(通过=1241, 缺能力=406, 不适用=4779, 失败=0),
                   delta={k: counts[k] - n for k, n in [('通过', 1241), ('缺能力', 406),
                                                       ('不适用', 4779), ('失败', 0)]},
                   owned_proxies=len(proxy_ids))
    (DEST / 'acceptance-summary.json').write_text(json.dumps(summary, ensure_ascii=False,
                                                            indent=2) + '\n', encoding='utf-8')
    print(json.dumps(summary, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    run()
