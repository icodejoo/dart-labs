"""从原始 LCOV 检查六个内核文件，拒绝缺失文件和零计数。"""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
FILES = ('client', 'pipeline', 'context', 'request', 'response', 'transport')
if '--b4' in sys.argv:
    FILES += ('plugins/mock', 'plugins/share', 'plugins/cache', 'plugins/offline')
    sys.argv.remove('--b4')
if '--b3' in sys.argv:
    FILES += ('plugins/retry', 'plugins/breaker', 'plugins/auth', 'options')
    sys.argv.remove('--b3')
if '--b2' in sys.argv:
    FILES += ('config', 'plugins/loading', 'plugins/notify', 'plugins/repath',
              'plugins/filter', 'plugins/timeout', 'plugins/envs')
    sys.argv.remove('--b2')


def inspect(path):
    """输出逐文件 LF/LH/BRF/BRH，并对原始命中记录独立复算。"""
    found = {}
    for block in path.read_text(encoding='utf-8').split('end_of_record'):
        lines = block.splitlines()
        source = next((line[3:].replace('\\', '/') for line in lines if line.startswith('SF:')), '')
        if '/lib/src/' not in source:
            continue
        name = source.split('/lib/src/', 1)[1].removesuffix('.dart')
        if name not in FILES:
            continue
        assert name not in found, f'重复文件 {source}'
        rows = [line[3:].split(',') for line in lines if line.startswith('DA:')]
        branches = [line[5:].split(',') for line in lines if line.startswith('BRDA:')]
        counts = (len(rows), sum(int(row[1]) > 0 for row in rows),
                  len(branches), sum(row[3] != '-' and int(row[3]) > 0 for row in branches))
        declared = {line.split(':')[0]: int(line.split(':')[1]) for line in lines
                    if line.startswith(('LF:', 'LH:', 'BRF:', 'BRH:'))}
        # 当前运行器只写 DA/BRDA；若有汇总字段则必须与逐项复算一致。
        for key, count in zip(('LF', 'LH', 'BRF', 'BRH'), counts):
            if key in declared:
                assert count == declared[key], (source, key)
        found[name] = counts
    assert set(found) == set(FILES), f'缺文件: {set(FILES) - set(found)}'
    print('file LF LH BRF BRH')
    for name in FILES:
        lf, lh, brf, brh = found[name]
        print(name + '.dart', lf, lh, brf, brh)
        assert lf > 0 and brf > 0 and lf == lh and brf == brh, name
    if 'plugins/auth' in FILES:
        interface = ROOT / 'lib/src/token_manager.dart'
        assert interface.is_file() and 'abstract interface class DiomanTokenManager' in interface.read_text(encoding='utf-8')
        print('token_manager.dart 0 0 0 0 (abstract interface: no executable lines/branches; source verified)')
    if 'plugins/cache' in FILES:
        interface = ROOT / 'lib/src/cache_store.dart'
        assert interface.is_file() and 'abstract interface class DiomanCachePersist' in interface.read_text(encoding='utf-8')
        print('cache_store.dart 0 0 0 0 (abstract interface: no executable lines/branches; source verified)')
    print(f'{len(FILES)} files present; nonzero counters; lines=100%; branches=100%; PASS')


if __name__ == '__main__':
    inspect(ROOT / (sys.argv[1] if len(sys.argv) > 1 else 'coverage/b1.info'))
