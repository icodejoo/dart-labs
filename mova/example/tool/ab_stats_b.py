"""Stats for Q13V A/B logs (resume error, stratified by skipToCommit). / Q13V 新旧对照统计，按 skipToCommit 分层。"""
import re, glob, os, statistics as st
d = {'new': [], 'old': []}
fails = {'new': 0, 'old': 0}
base = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'coverage_evidence', 'zero-copy-ab', 'b-vod')
for f in sorted(glob.glob(os.path.join(base, '*.log'))):
    k = os.path.basename(f)[:3]
    for l in open(f, encoding='utf-8'):
        m = re.search(r'VERDICT Q13V (PASS|FAIL) (.*)', l)
        if not m:
            continue
        kv = dict(re.findall(r'(\w+)=(-?\w+)', m.group(2)))
        if m.group(1) == 'FAIL':
            fails[k] += 1
        if kv.get('resumeErr', 'null') != 'nullms' and 'resumeErr' in kv:
            d[k].append((int(kv['resumeErr'].replace('ms', '')), int(kv['skipToCommit'].replace('ms', ''))))
for k, v in d.items():
    e = [x[0] for x in v]
    print(k, 'n', len(v), 'fail', fails[k], 'median', st.median(e), 'max', max(e), 'min', min(e), 'mean', round(st.mean(e)))
    for name, sel in (('ready(skip->commit<300)', [x for x in v if x[1] < 300]), ('waited(>=300)', [x for x in v if x[1] >= 300])):
        e2 = [x[0] for x in sel]
        if e2:
            print('  ', name, 'n', len(e2), 'median', st.median(e2), 'max', max(e2), 'min', min(e2), sorted(e2))
