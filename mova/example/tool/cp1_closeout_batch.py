"""CP1 gap reruns through run_matrix.Driver.batch (bounded Windows job object)."""
import argparse
import json
import sys
from types import SimpleNamespace

import run_matrix as matrix


def completion_identity(run_id):
    return dict(run_id=run_id+'-host', nativeRunId=run_id)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('group', choices=['cp0-h28', 'skin', 'keepalive-core'])
    p.add_argument('--run-id', required=True)
    p.add_argument('--worker', action='store_true')
    args = p.parse_args()
    result_path = matrix.TOOL/'coverage_evidence'/f'{args.run_id}-completion.json'
    if args.worker:
        if args.group == 'keepalive-core':
            import re
            import cp1_supplement
            cp1_supplement.keepalive(args.run_id)
            directory = matrix.TOOL/'coverage_evidence'/('matrix-'+args.run_id)
            raw = json.loads((directory/'supplement-result.json').read_text(encoding='utf-8'))
            text = '\n'.join(p.read_text(encoding='utf-8') for p in directory.glob('*.log')
                             if p.name.endswith('keepalive-core.log'))
            verdicts = [dict(case=f'gap:{s}.native.{i}', status=status, detail=detail)
                        for i, (s, status, detail) in enumerate(re.findall(
                            r'VERDICT (S1|S13) (PASS|FAIL) ([^\r\n]*)', text))]
            result = dict(**completion_identity(args.run_id), group=args.group,
                completed=bool(verdicts) and all(r['kind'] == 'OK' for r in raw.values()),
                harness=[r for r in raw.values() if r['kind'] == 'HARNESS'],
                verdicts=verdicts, evidence=[str(directory)])
            result_path.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
            return 0 if result['completed'] and not result['harness'] else 1
        import cp0_android_extra as extra
        extra.prepare()
        results = [extra.run_one(args.run_id, args.group, 30 if args.group == 'cp0-h28' else 1,
                                skins='default,bilibili')]
        if args.group == 'skin':
            results += [extra.run_one(args.run_id+f'-{i}', 'skin', 1,
                                     skins='default,bilibili') for i in (1, 2)]
        result = dict(**completion_identity(args.run_id), group=args.group,
                      completed=all(r['completed'] for r in results),
                      harness=[e for r in results for e in r['harness']],
                      verdicts=[v for r in results for v in r['verdicts']],
                      evidence=[r['evidence'] for r in results])
        result_path.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
        return 1 if result['harness'] or not result['completed'] or any(
            v['status'] == 'FAIL' for v in result['verdicts']) else 0
    manifest = json.loads(matrix.MANIFEST.read_text(encoding='utf-8'))
    manifest['ports'] = [18080, 18082, 18083] if args.group == 'keepalive-core' else [18085, 18086, 18082, 18083, 18084]
    d = matrix.Driver(SimpleNamespace(run_id=args.run_id+'-host'), manifest)
    try:
        d.preflight()
        return 0 if d.batch(dict(id='gap-'+args.group, description='CP1收口重跑',
            why='原始原生证据与逐项判据',
            argv=['{python}', '{tool}/cp1_closeout_batch.py', args.group,
                  '--run-id', args.run_id, '--worker'], timeout=5400,
            native_driver=True, result_path=str(result_path))) else 1
    finally:
        # The native worker saves/restores all mappings itself. Driver.batch's
        # legacy 18082 bookkeeping must not remove its already-restored mapping.
        d.mappings.clear()
        d.cleanup()


if __name__ == '__main__':
    sys.exit(main())
