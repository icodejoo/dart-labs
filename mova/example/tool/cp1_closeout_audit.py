"""Audit immutable native completions separately from the old host-ID adapter bug."""
from collections import Counter
import hashlib
import json
from pathlib import Path
import re

from cp1_closeout_batch import completion_identity
import run_matrix as matrix


def main():
    evidence = matrix.TOOL/'coverage_evidence'
    jobs = [('cp1-close-h28-r3-1818', 'cp0-h28', 90),
            ('cp1-close-skin-1825', 'skin', 222),
            ('cp0-close-keepalive-core-1949', 'keepalive-core', 20),
            ('cp1-close-keepalive-core-1955', 'keepalive-core', 20)]
    checks = []
    for native_run, group, count in jobs:
        path = evidence/(native_run+'-completion.json')
        raw_bytes = path.read_bytes()
        data = json.loads(raw_bytes)
        host = (evidence/(native_run+'.host.log')).read_text(encoding='utf-8')
        codes = re.findall(r'<case=gap-'+re.escape(group)+r'> END exit=(-?\d+)', host)
        assert codes == ['0'], (native_run, codes)
        assert len(data['verdicts']) == count
        assert not any(v['status'] == 'FAIL' for v in data['verdicts'])
        native_kind = matrix.gap_result_kind(data, native_run, group, 0)
        mapped = dict(data, **completion_identity(native_run))
        host_kind = matrix.gap_result_kind(mapped, native_run+'-host', group, 0)
        assert native_kind == host_kind == 'OK'
        unchanged = {k: v for k, v in data.items() if k != 'run_id'} == {
            k: v for k, v in mapped.items() if k not in ('run_id', 'nativeRunId')}
        assert unchanged and path.read_bytes() == raw_bytes
        if group == 'cp0-h28':
            for mode in ('playing', 'paused', 'cutover'):
                rows = [v for v in data['verdicts'] if v['case'].endswith('.'+mode)]
                assert sorted(v['actual']['iteration'] for v in rows) == list(range(30))
                assert all(abs(v['actual']['deltaMs']) <= 500 and v['actual']['path'] == v['expectedPath'] for v in rows)
        if group == 'skin':
            for directory in data['evidence']:
                skin = json.loads((Path(directory)/'cp0-result.json').read_text())
                assert all(skin['verdicts'][i]['status'] == 'PASS' and
                           'lockToggle@overlay' in skin['verdicts'][i]['actual']['tree'] for i in (6, 8, 56, 61))
        checks.append(dict(nativeRunId=native_run, hostRunId=native_run+'-host', group=group,
            evidence=path.relative_to(matrix.ROOT).as_posix(), sha256=hashlib.sha256(raw_bytes).hexdigest(),
            counts=dict(Counter(v['status'] for v in data['verdicts'])), workerExit=0,
            nativeValidation=native_kind, correctedHeaderValidation=host_kind,
            nativeDataUnchanged=unchanged, oldHostHarnessRetained=True))
    target = evidence/'cp1-closeout-native-audit.json'
    target.write_text(json.dumps(dict(passed=True, checks=checks), ensure_ascii=False, indent=2), encoding='utf-8')
    print('Native completion audit PASS:', len(checks), 'immutable datasets')


if __name__ == '__main__':
    main()
