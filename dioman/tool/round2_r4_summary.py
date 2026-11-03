"""R4 成对实验的机械汇总；不以不稳定测量宣称达标。"""
import argparse
import hashlib
import json
from pathlib import Path
import statistics

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'docs/reports/round2-r4-evidence'


def paired(name, kind):
    """按吞吐中位数选整行，目标阈值与副作用阈值单列。"""
    dest = OUT / name / kind
    runs = {variant: [json.loads((dest / f'{i}-{variant}.json').read_text())
                      for i in range(1, 4)] for variant in ('before', 'after')}
    result = {}
    for index, row in enumerate(runs['before'][0]['results']):
        scenario = row['scenario']
        data = {}
        for variant, rounds in runs.items():
            samples = [run['results'][index] for run in rounds]
            speed = lambda value: value.get('opsPerSecond', 1000000/value['meanMicros'])
            median = sorted(samples, key=speed)[1]
            spread = (max(map(speed, samples))/min(map(speed, samples))-1)*100
            data[variant] = dict(samples=samples, median=median,
                                 selectedRound=samples.index(median)+1,
                                 spreadPercent=spread, stable=spread < 10)
        before = data['before']['median']['meanMicros']
        after = data['after']['median']['meanMicros']
        data['improvementMicros'] = before-after
        data['improvementPercent'] = (before-after)/before*100
        data['targetThresholdMet'] = before-after >= 2 or (before-after)/before >= .05
        data['regressionThresholdMet'] = after/before <= 1.03
        result[scenario] = data
    result_path = dest / 'summary.json'
    result_path.write_text(json.dumps(result, indent=2)+'\n', encoding='utf-8')
    for scenario, row in result.items():
        print(scenario, 'delta us', round(row['improvementMicros'], 3),
              'delta %', round(row['improvementPercent'], 3),
              'stable', row['before']['stable'] and row['after']['stable'],
              'regression<=3%', row['regressionThresholdMet'])
    return result


def clone():
    """克隆开关使用相邻同轮差，列出三轮和中位数。"""
    dest = OUT / 'clone'
    samples = []
    for i in range(1, 4):
        values = {mode: json.loads((dest / f'{i}-clone-{mode}.json').read_text())['results'][0]['meanMicros']
                  for mode in ('off', 'on')}
        samples.append(dict(round=i, **values, deltaMicros=values['on']-values['off']))
    result = dict(samples=samples,
                  medianPairedDeltaMicros=statistics.median(row['deltaMicros'] for row in samples),
                  spreads={mode: (max(row[mode] for row in samples)/min(row[mode] for row in samples)-1)*100
                           for mode in ('off', 'on')})
    result['stable'] = all(value < 10 for value in result['spreads'].values())
    (dest / 'summary.json').write_text(json.dumps(result, indent=2)+'\n', encoding='utf-8')
    print(json.dumps(result, indent=2))


def decide(name):
    """按事前阈值作去留，撤回时恢复登记的改前原字节。"""
    pipeline = paired(name, 'pipeline')
    target = (pipeline['S3'] if name == 'request-copy'
              else paired(name, 'micro')['strict-json'])
    stable = all(row[variant]['stable'] for row in pipeline.values()
                 for variant in ('before', 'after'))
    stable = stable and all(target[variant]['stable'] for variant in ('before', 'after'))
    side = all(row['regressionThresholdMet'] for scenario, row in pipeline.items()
               if name != 'request-copy' or scenario != 'S3')
    keep = stable and target['targetThresholdMet'] and side
    source = ROOT / 'coverage/r4-variants' / name / ('after' if keep else 'before')
    restored = {}
    for path in source.rglob('*.dart'):
        relative = path.relative_to(source)
        content = path.read_bytes()
        (ROOT / relative).write_bytes(content)
        digest = hashlib.sha256(content).hexdigest()
        assert hashlib.sha256((ROOT / relative).read_bytes()).hexdigest() == digest
        restored[relative.as_posix()] = digest
    result = dict(keep=keep, stable=stable,
                  targetThresholdMet=target['targetThresholdMet'],
                  otherRegressionWithin3Percent=side, final_sha256=restored)
    (OUT / name / 'decision.json').write_text(json.dumps(result, indent=2)+'\n', encoding='utf-8')
    print(json.dumps(result, indent=2))


def main():
    """选择成对实验或克隆成本的汇总。"""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('name')
    parser.add_argument('--kind', default='pipeline', choices=['pipeline', 'micro'])
    parser.add_argument('--decide', action='store_true')
    args = parser.parse_args()
    if args.decide:
        decide(args.name)
    elif args.name == 'clone':
        clone()
    else:
        paired(args.name, args.kind)


if __name__ == '__main__':
    main()
