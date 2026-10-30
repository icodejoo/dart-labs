"""Stats for Q13AS A/B logs: verdicts, stuck shadows (no numeric pos before abandon), load latency. / Q13AS 新旧对照统计。"""
import re, glob, os, statistics as st
base = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'coverage_evidence', 'zero-copy-ab', 'c-as')
res = {'new': {'pass': 0, 'fail': 0, 'stuck': [], 'load': []}, 'old': {'pass': 0, 'fail': 0, 'stuck': [], 'load': []}}
for f in sorted(glob.glob(os.path.join(base, '*.log'))):
    k = os.path.basename(f)[:3]
    r = res[k]
    run = 0
    cur = None  # shadow idx -> first numeric pos seen
    seen = {}
    for l in open(f, encoding='utf-8'):
        if '--- Q13AS' in l:
            run += 1
            seen = {}
        m = re.search(r'DIAG A shadow k(\d+) t=(\d+)ms pos=(\S*) .*idle=(\S+)', l)
        if m:
            i, t, pos = m.group(1), int(m.group(2)), m.group(3)
            e = seen.setdefault(i, {'first': None, 'last_t': 0, 'gone': False})
            e['last_t'] = t
            if pos == 'gone':
                e['gone'] = True
            else:
                try:
                    if float(pos) > 0 and e['first'] is None:
                        e['first'] = t
                except ValueError:
                    pass
        m = re.search(r'A shadow k(\d+) loaded (\d+)ms', l)
        if m:
            r['load'].append(int(m.group(2)))
        m = re.search(r'VERDICT Q13A (PASS|FAIL)', l)
        if m:
            r['pass' if m.group(1) == 'PASS' else 'fail'] += 1
            for i, e in seen.items():
                if e['first'] is None and e['last_t'] > 4000:
                    r['stuck'].append((os.path.basename(f), run, 'k' + i, e['last_t'], e['gone']))
            seen = {}
for k, r in res.items():
    L = r['load']
    print(k, 'pass', r['pass'], 'fail', r['fail'], 'stuck', len(r['stuck']), r['stuck'])
    if L:
        print('   load n', len(L), 'median', st.median(L), 'max', max(L), 'p>3000:', sum(1 for x in L if x > 3000), sorted(L)[-5:])
