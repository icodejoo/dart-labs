"""Evidence-only matrix reducer. Rules name observations, never verdicts.

Only direct command segments are consumed: cumulative API snapshots must not
reintroduce earlier runs. JSON lists (UI_CHECK), event payloads and legacy
script VERDICT lines are supported alongside CHECK records.
"""
import fnmatch
import json
from pathlib import Path
import re

ALIASES = {'MovaSwapChange': 'MovaCutoverChange',
           'MovaStandbyChange': 'MovaKeepAliveChange',
           'MovaStandbyResume': 'MovaKeepAliveResume'}
SCALARS = {'MovaDurationChange': ('duration','duration'),
 'MovaBufferChange': ('buffering','buffering'), 'MovaVolumeChange': ('value','volume'),
 'MovaBrightChange': ('value','brightness'), 'MovaRateChange': ('value','rate'),
 'MovaFitChange': ('fit','fit'), 'MovaZoomChange': ('zoom','zoom'),
 'MovaLockChange': ('value','locked'), 'MovaFullScreenChange': ('value','fullscreen'),
 'MovaOrientationChange': ('orientation','orientation'), 'MovaMiniChange': ('mini','mini'),
 'MovaPipChange': ('value','pip'), 'MovaQualityChange': ('quality','quality'),
 'MovaQualityListChange': ('qualities','qualities'),
 'MovaTimeShiftChange': ('behind','timeshiftBehind'), 'MovaKeepAliveChange': ('phase','keepAlive')}


def status(values):
    """Failure wins; unknown/missing observations cannot pass."""
    return 'FAIL' if 'FAIL' in values else 'BLOCKED' if not values or 'BLOCKED' in values else 'PASS'


class Evidence:
    def __init__(self, out, prefix):
        self.records = []
        self.checks = {}
        self.logs = {}
        self.errors = []
        self.files = set()
        self.texts={p.name:p.read_text(encoding="utf-8",errors="replace") for p in Path(out).glob(prefix+"*.txt")}
        for path in sorted(Path(out).glob(prefix + '*.json')):
            # CP0 has its own measurement ledger (us stamps / *Ms state keys).
            # It cannot supply or invalidate v1's legacy event assertions.
            if path.name.startswith(prefix+'cp0-'):continue
            # Derived ledgers/audits are deliberately not accepted.
            if any(s in path.name for s in ('ledger', 'summary', 'audit', 'review', 'gap.json', 'recent-events')):
                continue
            try:
                data = json.loads(path.read_text(encoding='utf-8'))
            except (OSError, ValueError) as e:
                self.errors.append(f'{path.name}: {e}')
                continue
            self.files.add(path.name[len(prefix):])
            start=0
            if isinstance(data, list):
                records = [dict(r, kind='CHECK') for r in data if isinstance(r, dict) and 'pass' in r and 'id' in r]
            elif isinstance(data, dict):
                records = data.get('records', [])
                if not isinstance(records, list):
                    self.errors.append(f'{path.name}: records 非数组'); continue
                if any(not isinstance(r,dict) for r in records):
                    self.errors.append(f'{path.name}: records 含非对象记录'); continue
                start = max((i for i,r in enumerate(records) if r.get('kind') == 'BEGIN'), default=0)
                records = records[start:]
                if records and data.get('status') not in ('done', None):
                    self.errors.append(f'{path.name}: 命令未完成 status={data.get("status")}')
                    continue
            else:
                continue
            for i, r in enumerate(records):
                pointer = f'{path.name}:records[{i+start}]'
                self.records.append((r,pointer))
                if r.get('kind') == 'CHECK':
                    self.checks.setdefault(r.get('id'), []).append((r,pointer))
        for path in sorted(Path(out).glob(prefix + '*.log')):
            if '.driver.' in path.name: continue
            content = path.read_text(encoding='utf-8', errors='replace')
            self.logs[path.name[len(prefix):]] = (content,path.name)
            for line_no, line in enumerate(content.splitlines(), 1):
                match = re.search(r'MATRIX_RECORD (\{.*\})', line)
                if not match: continue
                try:
                    row = json.loads(match[1])
                    if not isinstance(row, dict): raise ValueError('record 非对象')
                except ValueError as error:
                    self.errors.append(f'{path.name}:line[{line_no}]: {error}'); continue
                # Only completed scripts may contribute structured log records.
                if not any(s in content for s in ('AUTORUN DONE', 'ALL_DONE', '|DONE|')): continue
                pointer = f'{path.name}:line[{line_no}]'
                self.records.append((row, pointer))
                if row.get('kind') == 'CHECK':
                    self.checks.setdefault(row.get('id'), []).append((row, pointer))

    def check(self, ident, minimum=1, missing=None, sources=None, assertions=None, **kw):
        samples = self.checks.get(ident, [])
        if not samples: return 'BLOCKED', f'缺 CHECK {ident}'+('：'+missing if missing else '')
        vals = ['PASS' if r.get('pass') is True else 'FAIL' if r.get('pass') is False else 'BLOCKED' for r,_ in samples]
        # New CHECKs retain numeric inputs. Recompute their declared predicates
        # rather than trusting a producer's boolean alone.
        if assertions:
            vals += [self.assertions(r, assertions) if type(r.get('pass')) is bool else 'BLOCKED'
                     for r, _ in samples]
        if len(samples)<minimum:vals.append('BLOCKED')
        absent=[f for f in (sources or []) if not any(fnmatch.fnmatch(p.split(':records')[0], '*'+f) for _,p in samples)]
        if absent:vals.append('BLOCKED')
        return status(vals), ('缺来源 '+str(absent)+'；' if absent else '')+'; '.join(f'{p}: {json.dumps(r,ensure_ascii=False)}' for r,p in samples)

    @staticmethod
    def assertions(record, assertions):
        def field(key):
            value = record
            for part in key.split('.'):
                value = value[int(part)] if isinstance(value, list) else value[part]
            return value
        def quality_shape(value):
            return isinstance(value,dict) and set(value)=={'label','uri','bandwidth','width','height','isAuto'}
        try:
            for clause in assertions:
                actual = field(clause['field'])
                expected = field(clause['other']) if 'other' in clause else clause.get('value')
                # Native producers use null for an unparsed observation. A
                # comparison to a missing baseline is also unknown. Explicit
                # null contracts (e.g. heartbeat disabled) remain comparable.
                if (actual is None and expected is not None) or ('other' in clause and expected is None and not clause.get('nullable', False)):
                    return 'BLOCKED'
                op = clause['op']
                if op == 'eq': ok = actual == expected
                elif op == 'ge': ok = actual >= expected
                elif op == 'le': ok = actual <= expected
                elif op == 'lt': ok = actual < expected
                elif op == 'near': ok = abs(actual - expected) <= clause.get('tolerance', 0)
                elif op == 'delta_le':
                    baseline = field(clause['baseline'])
                    if baseline is None: return 'BLOCKED'
                    ok = actual - baseline <= expected
                elif op == 'one_of': ok = any(type(actual) is type(v) and actual == v for v in expected)
                elif op == 'cpu_per_media_le':
                    def rate(sample):
                        before, after = sample['before'], sample['after']
                        p0, p1 = before['properties']['time-pos'], after['properties']['time-pos']
                        if p0['error'] != 'success' or p1['error'] != 'success': return None
                        span = p1['data'] - p0['data']
                        if span < clause['minimum_media_seconds']: return None
                        return (after['cpuTicks'] - before['cpuTicks']) / span
                    left, right = rate(actual), rate(expected)
                    if left is None or right is None: return 'BLOCKED'
                    ok = left >= 0 and right >= 0 and left <= right * clause['scale']
                elif op == 'contains': ok = expected in actual
                elif op == 'list_length': ok = isinstance(actual, list) and len(actual) == expected
                elif op == 'quality_shape': ok = actual is None or quality_shape(actual)
                elif op == 'quality_list_shape': ok = isinstance(actual,list) and all(quality_shape(v) for v in actual)
                elif op == 'prefix_count': ok = isinstance(actual, list) and all(isinstance(v,str) for v in actual) and sum(v.startswith(clause['prefix']) for v in actual) == expected
                elif op == 'count_where':
                    ok = isinstance(actual, list) and all(isinstance(v,dict) for v in actual) and sum(
                        all(v.get(k) == value for k,value in clause['where'].items()) for v in actual) == expected
                elif op == 'all_lt': ok = isinstance(actual, list) and bool(actual) and all(v < expected for v in actual)
                elif op == 'all_eq': ok = isinstance(actual, list) and bool(actual) and all(v == expected for v in actual)
                elif op == 'nonempty': ok = isinstance(actual, (str, list, dict)) and len(actual) > 0
                else: return 'BLOCKED'
                if not ok: return 'FAIL'
        except (KeyError, TypeError, ValueError):
            return 'BLOCKED'
        return 'PASS'

    def event(self, name, **kw):
        name = ALIASES.get(name,name)
        samples = [(r,p) for r,p in self.records if r.get('kind')=='EVENT' and r.get('event')==name]
        if not samples: return 'BLOCKED', f'缺 EVENT {name}'
        vals=[]; details=[]
        for r,p in samples:
            payload, state = r.get('payload',{}),r.get('state',{})
            if name in SCALARS:
                a,b=SCALARS[name]
                value = 'BLOCKED' if a not in payload or b not in state else 'PASS' if payload[a]==state[b] else 'FAIL'
            elif name=='MovaSizeChange':
                value='BLOCKED' if not {'width','height'} <= payload.keys() or 'size' not in state else 'PASS' if f'{payload["width"]}x{payload["height"]}'==state['size'] else 'FAIL'
            else:
                value='PASS' if isinstance(r.get('ms'),(int,float)) and isinstance(r.get('payload'),dict) and isinstance(r.get('state'),dict) else 'BLOCKED'
            vals.append(value)
            if value!='PASS' or not details:details.append(f'{p}: {json.dumps(r,ensure_ascii=False)}')
        return status(vals),f'{name} 样本={len(samples)}；'+'; '.join(details[:8])

    def log(self, file, name, minimum=1, **kw):
        content,pointer = self.logs.get(file, ('', file))
        if not any(s in content for s in ('AUTORUN DONE','ALL_DONE','|DONE|')):
            return 'BLOCKED', f'{pointer}: 缺完成标记'
        lines = [l for l in content.splitlines() if re.search(r'(?:VERDICT '+re.escape(name)+r' |\|RESULT\|'+re.escape(name)+r'\|[^|]+\||\b'+re.escape(name)+r' )(?:PASS|FAIL|BLOCKED)\b',l)]
        vals = [re.search(r'\b(PASS|FAIL|BLOCKED)\b',l).group(1) for l in lines]
        if len(lines)<minimum:vals.append('BLOCKED')
        return status(vals), f'{pointer}: {name} 样本={len(lines)}/{minimum}; '+'; '.join(lines)

    def keepalive_wake(self, file='keepalive-core.log', minimum=9, **kw):
        """H42 is undecided: grace alone cannot establish a decoded wake."""
        content, pointer = self.logs.get(file, ('', file))
        rows = re.findall(r'S1 gop=.*?phase=(\w+).*?signal=(\w+).*?decodedProp=(\w+)ms vid=(\S+) mute=(\S+)', content)
        values = []
        for phase, signal, decoded, vid, mute in rows:
            if phase != 'holding' or vid in ('no', '0') or mute != 'no': values.append('FAIL')
            elif signal in ('grace', 'timeout', 'null') or not decoded.isdigit(): values.append('BLOCKED')
            else: values.append('PASS')
        if len(rows) < minimum or 'AUTORUN DONE' not in content: values.append('BLOCKED')
        return status(values), f'{pointer}: S1 raw={rows}; H42 grace/elapsed 语义待决，需 RESTART/size 与原生解码事件关联'

    def record(self, name, assertions, files='*', where=None, minimum=1, **kw):
        def field(r,key):
            for part in key.split('.'):
                r=r[part]
            return r
        samples=[(r,p) for r,p in self.records if r.get('kind')==name
                 and fnmatch.fnmatch(p.split(':records')[0], '*'+files)
                 and all(r.get(k)==v for k,v in (where or {}).items())]
        vals=[];details=[]
        for r,p in samples:
            value='PASS'
            try:
                for a in assertions:
                    actual=field(r,a['field']); expected=field(r,a['other']) if 'other' in a else a.get('value')
                    op=a['op'];tol=a.get('tolerance',0)
                    ok = (actual==expected if op=='eq' else
                          abs(actual-expected)<=tol if op=='near' else
                          actual>=expected if op=='ge' else actual<=expected if op=='le' else
                          expected in actual if op=='contains' else
                          abs(actual-max(a['low'],min(a['high'],field(r,a['input']))))<=tol if op=='clamp' else
                          all(v in actual for v in expected) if op=='containsAll' else False)
                    if not ok:value='FAIL'
            except (KeyError,TypeError,ValueError):value='BLOCKED'
            vals.append(value);details.append(f'{p}: {json.dumps(r,ensure_ascii=False)}')
        if len(samples)<minimum:vals.append('BLOCKED')
        return status(vals), f'{name} 样本={len(samples)}/{minimum} files={files}; '+('; '.join(details) or '缺事件记录')

    def rate_sequence(self, **kw):
        vals=[];details=[]
        for file in ('rerun-batch15-basic.json','rerun-batch15-basic-cutover.json'):
            rows=[(r,p) for r,p in self.records if p.split(':records')[0].endswith(file)]
            requests=[r['input'] for r,p in rows if r.get('kind')=='RATE']
            actual=[r.get('payload',{}).get('value') for r,p in rows if r.get('kind')=='EVENT' and r.get('event')=='MovaRateChange']
            expected=[max(.25,min(4,v)) for v in requests]
            cursor=0
            for v in actual:
                if cursor<len(expected) and v==expected[cursor]:cursor+=1
            vals.append('BLOCKED' if len(requests)<6 else 'PASS' if cursor==len(expected) else 'FAIL')
            details.append(f'{file}: requested={requests}, clamped={expected}, EVENT values={actual}, matched={cursor}')
        return status(vals), '; '.join(details)

    def volume(self, **kw):
        values=[];details=[]
        for mode in ('engine','cutover'):
            for v in (-10,0,1,30,50,100,110):
                suffix=f'rerun-native-{mode}-volume{v}.native.txt'
                file=next((f for f in self.texts if f.endswith(suffix)),None)
                if not file:values.append('BLOCKED');details.append('缺 '+suffix);continue
                text=self.texts[file]
                match=re.search(r'volume is (\d+) in range \[(\d+)\.\.(\d+)\]',text)
                if not match:values.append('BLOCKED');details.append(file+': 缺原生音量读回');continue
                got,lo,hi=map(int,match.groups());target=lo+(hi-lo)*max(0,min(100,v))/100
                # Android volume is quantized to integer steps.
                values.append('PASS' if abs(got-target)<=1 else 'FAIL')
                details.append(f'{file}: input={v} native={got} range={lo}..{hi} expected={target} tolerance=1step')
        return status(values), '; '.join(details)

    def lifecycle(self, **kw):
        samples=[(r,p) for r,p in self.records if r.get('kind')=='LIFECYCLE']
        values=[];details=[]
        expected=['MovaPlay','MovaSourceChange','MovaReady','MovaDurationChange','MovaSizeChange','MovaFirstFrame','MovaDone']
        for r,p in samples:
            events=r.get('events',[]);cursor=0
            for e in events:
                if cursor<len(expected) and e==expected[cursor]:cursor+=1
            values.append('PASS' if cursor==len(expected) and not r.get('errors') else 'FAIL')
            details.append(f'{p}: {json.dumps(r,ensure_ascii=False)}')
        return status(values), '; '.join(details) or '缺自然生命周期事件序列'

    def duration(self, **kw):
        samples=[(r,p) for r,p in self.records if r.get('kind')=='LIVE_DURATION']
        vals=[];details=[]
        modes=set()
        for r,p in samples:
            step=r.get('step');ds=[v['duration'] for v in r.get('samples',[])];modes.add(step)
            pairs=[(a,b) for a,b in zip(ds,ds[1:]) if a>0 and b>0]
            vals.append('PASS' if pairs and all(b-a>=step for a,b in pairs) else 'FAIL' if pairs else 'BLOCKED')
            details.append(f'{p}: step={step} durations={ds}')
        if not {0,2000}<=modes:vals.append('BLOCKED')
        return status(vals), '; '.join(details) or '缺 LIVE_DURATION step0/2000'

    def hls(self, variants=None, minimum=1, **kw):
        samples=[(r,p) for r,p in self.records if r.get('kind')=='HLS_RESULT']
        vals=[];details=[]
        for r,p in samples:
            if r.get('harnessInvalid'):v='BLOCKED'
            elif type(r.get('pass')) is bool:v='PASS' if r['pass'] else 'FAIL'
            else:v='BLOCKED'
            vals.append(v); details.append(f'{p}: {json.dumps(r,ensure_ascii=False)}')
        for variant in variants or []:
            count=sum(all(r.get(k)==v for k,v in variant.items()) for r,p in samples)
            if count<minimum:vals.append('BLOCKED');details.append('缺 HLS 模式 '+str(variant)+f' 样本 {count}/{minimum}')
        return status(vals), '缺 HLS_RESULT' if not samples else '; '.join(details)


def reduce_evidence(manifest, out, prefix, rules=None):
    rules = rules or json.loads((Path(__file__).with_name('matrix_rules.json')).read_text(encoding='utf-8'))
    ev=Evidence(out,prefix); verdicts={}
    manual={r['id']:r['reason'] for r in manifest['manual']}
    for ident in manifest['ids']:
        subs=[]
        rule=rules[ident]
        for n,spec in enumerate(rule.get('requires', [])):
            kind=spec['kind']; args={k:v for k,v in spec.items() if k!='kind'}
            try:
                value,detail=getattr(ev,kind)(**args)
            except Exception as error:
                value,detail='BLOCKED',f'验证器错误 {kind}: {type(error).__name__}: {error}'
            subs.append(dict(id=f'{ident}/{kind}:{spec.get("ident",spec.get("name",n))}',status=value,evidence=detail))
        # Do not discard an explicit false CHECK merely because another clause is missing.
        known={s.get('ident') for s in rule.get('requires',[]) if s['kind']=='check'}
        for key in ev.checks:
            if key not in known and (key==ident or key.startswith(ident+'.')) and key not in rules.get('_invalid_checks',{}):
                value,detail=ev.check(key)
                subs.append(dict(id=key,status=value,evidence=detail))
        missing=rule.get('missing',[])
        for clause in missing:
            subs.append(dict(id=ident+'/missing',status='BLOCKED',evidence='缺用例/判据：'+clause))
        # Invalid historical assertions are excluded. Their replacement is a
        # required rule; keeping the invalid boolean must not poison a rerun.
        if ev.errors:
            subs.append(dict(id=ident+'/evidence-errors',status='BLOCKED',evidence='证据解析错误：'+'; '.join(ev.errors)))
        if ident in manual:
            value='BLOCKED'; detail='manual 环境：'+manual[ident]
        else:
            value=status([s['status'] for s in subs])
            detail='；'.join(s['id']+': '+s['evidence'] for s in subs if s['status']!='PASS') or '全部必需子项 PASS'
        verdicts[ident]=dict(status=value,evidence=detail,subitems=subs,evidence_only=True)
    return verdicts
