"""按磁盘上的全部 pipeline 源文件复算 LCOV，不沿用分批白名单。"""
from pathlib import Path
import json
import sys

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / 'docs/reports/pipeline-b5a-evidence'
SOURCE = ROOT / 'lib/src/pipeline'


def inspect(path):
    """拒绝缺文件、重复 SF 和未覆盖计数；纯声明单独列明，不宣称空分母百分比。"""
    files = {p.relative_to(SOURCE).as_posix(): p for p in SOURCE.rglob('*.dart')}
    declarations = {
        'token_manager.dart': 'abstract interface class DiomanTokenManager',
        'cache_store.dart': 'abstract interface class DiomanCachePersist',
        'stages.dart': 'const diomanBuiltinStages',
    }
    found = {}
    for block in path.read_text(encoding='utf-8').split('end_of_record'):
        lines = block.splitlines()
        source = next((s[3:].replace('\\', '/') for s in lines if s.startswith('SF:')), '')
        marker = '/lib/src/pipeline/'
        if marker not in source:
            continue
        name = source.split(marker)[1]
        assert name in files and name not in found, name
        rows = [s[3:].split(',') for s in lines if s.startswith('DA:')]
        branches = [s[5:].split(',') for s in lines if s.startswith('BRDA:')]
        if name not in declarations:
            assert rows and branches, f'{name}: missing line/branch instrumentation'
        counts = [len(rows), sum(int(r[1]) > 0 for r in rows),
                  len(branches), sum(r[3] != '-' and int(r[3]) > 0 for r in branches)]
        found[name] = counts
        missed = [r for r in rows if int(r[1]) == 0]
        missed += [r for r in branches if r[3] == '-' or int(r[3]) == 0]
        assert not missed, (name, missed)
        for key, count in zip(('LF', 'LH', 'BRF', 'BRH'), counts):
            summary = [int(s.split(':')[1]) for s in lines if s.startswith(key + ':')]
            assert not summary or summary == [count], (name, key)
    assert set(files) - set(found) <= set(declarations), set(files) - set(found)
    for name, marker in declarations.items():
        source = files[name].read_text(encoding='utf-8')
        assert marker in source
        # 与磁盘全部源文件一一对照；声明文件不得偷偷产生未计数的方法体。
        code = '\n'.join(s for s in source.splitlines() if not s.lstrip().startswith('///'))
        assert '=>' not in code and 'return ' not in code, name
        found.setdefault(name, [0, 0, 0, 0])
    assert set(found) == set(files)
    print('file LF LH BRF BRH')
    for name, counts in sorted(found.items()):
        assert name in declarations or counts[0] > 0, name
        print(name, *counts)
    (DEST / 'coverage.json').write_text(json.dumps(found, indent=2) + '\n', encoding='utf-8')
    print(f'{len(files)} source files accounted for; all executable lines/branches 100%; PASS')
    print('cache_store/token_manager: abstract contracts; stages: enums/const tables; no executable denominator')


if __name__ == '__main__':
    inspect(ROOT / (sys.argv[1] if len(sys.argv) > 1 else
                   'docs/reports/pipeline-b5a-evidence/coverage.info'))
