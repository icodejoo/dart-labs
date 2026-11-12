"""MET2只读自检：原始证据、预算来源、CPU推算、链接和授权写入边界。"""
import collections
import hashlib
import json
import math
import pathlib
import re
import statistics

ROOT = pathlib.Path(__file__).resolve().parents[5]
OUT = pathlib.Path(__file__).resolve().parent
MET2 = OUT.parent
BUILD = 'average_frame_build_time_millis'
RASTER = 'average_frame_rasterizer_time_millis'
BUILD_P99 = '99th_percentile_frame_build_time_millis'
COMBINED_P99 = '99th_percentile_build_plus_raster_millis'


def read(path):
    """读取UTF-8 JSON对象。"""
    return json.loads(path.read_text(encoding='utf-8'))


def main():
    """核对保存证据和实际输出，不连接设备或启动分析测试进程。"""
    docs = list((ROOT / 'docs').glob('*.md')) + [ROOT / 'README.md', ROOT / 'README.zh-CN.md',
                                               ROOT / 'tool/bench/README.md', MET2 / 'REPORT.md']
    broken = []
    links = 0
    for doc in docs:
        for target in re.findall(r'\]\(([^)\s]+)\)', doc.read_text(encoding='utf-8')):
            if target.startswith(('http:', 'https:', 'mailto:', '#')):
                continue
            target = target.split('#')[0]
            if target:
                links += 1
                if not (doc.parent / target).exists():
                    broken.append((str(doc.relative_to(ROOT)), target))
    assert not broken, broken
    guide = (ROOT / 'docs/IMPLEMENTATION_GUIDE.md').read_text(encoding='utf-8')
    section = guide.split('### 2.3 analysis_options.yaml', 1)[1].split('### 2.4', 1)[0]
    expected = re.search(r'```yaml\n(.*?)```', section, re.S).group(1).strip()
    assert (ROOT / 'analysis_options.yaml').read_text(encoding='utf-8').strip() == expected
    provenance = read(MET2 / 'provenance.json')
    assert provenance == read(ROOT / 'tool/bench/results/met/provenance.json')
    for item in provenance:
        assert hashlib.sha256((ROOT / item['source']).read_bytes()).hexdigest() == item['sha256']
    assessment = read(MET2 / 'assessment.json')
    scenes = assessment['scenarios']
    assert collections.Counter(s['status'] for s in scenes.values()) == {
        'PASS': 6, 'FAIL': 3, 'UNCERTAIN': 1, 'INFO': 1}
    cpu = {r['scenario']: r for r in read(MET2 / 'cpu_indicators.json')}
    p99_checks = 0
    for key, scene in scenes.items():
        if scene['clean_count'] is None:
            continue
        windows = scene['windows']
        clean = [w for w in windows if not w['backpressure_contaminated']]
        assert all(w['delivery_passed'] for w in windows)
        assert cpu[key]['ui_busy_ratio'] == statistics.median([w[BUILD] * w['fps'] / 1000 for w in windows])
        assert cpu[key]['raster_busy_ratio'] == statistics.median([w[RASTER] * w['fps'] / 1000 for w in clean])
        for metric, limit in [(BUILD_P99, 4), (COMBINED_P99, 12)]:
            guard = scene['frame_budget'][metric]
            assert guard['max'] == max(w[metric] for w in clean)
            assert guard['status'] == ('FAIL' if guard['max'] > limit else 'PASS')
            p99_checks += 1
    state = read(ROOT / 'tool/bench/budgets.status.json')['met2']
    for key, floors in state['calibrated_floors'].items():
        for metric, floor in floors.items():
            assert floor <= state['pre_met2_budgets'][key][metric]
    calibrated_count = 0
    unstable_count = 0
    budgets = read(ROOT / 'tool/bench/budgets.json')
    for key, scene in scenes.items():
        if scene['clean_count'] is None:
            continue
        for metric, row in scene['metrics'].items():
            if not metric.endswith('_millis') or row['status'] == 'INFO':
                continue
            if row['stable']:
                expected = math.ceil(row['median'] * 1.1 * 1000 - 1e-9) / 1000
                expected = max(expected, state['calibrated_floors'].get(key, {}).get(metric, 0))
                assert budgets[key][metric] == expected, (key, metric)
                calibrated_count += 1
            else:
                assert budgets[key][metric] == state['pre_met2_budgets'][key][metric]
                unstable_count += 1
    assert calibrated_count == 28 and unstable_count == 8
    assert len(read(MET2 / 'design_gaps.json')) == 14
    all_windows = read(ROOT / 'tool/bench/results/met/all_windows.json')
    assert len(all_windows) == 130 and all(w['delivery_passed'] for w in all_windows)
    changed = []
    for path, digest in read(OUT / 'before_hashes.json').items():
        current = ROOT / path
        if not current.exists() or hashlib.sha256(current.read_bytes()).hexdigest() != digest:
            changed.append(path)
    exact = {'README.md', 'README.zh-CN.md', 'test/ACCEPTANCE.md',
             'docs/METRIC_FIX_REPORT.md', 'docs/TEST_STRATEGY.md', 'docs/ARCHITECTURE.md',
             'docs/RELEASE_CHECKLIST.md', 'docs/README.md', 'docs/IMPLEMENTATION_GUIDE.md'}
    assert all(p in exact or (p.startswith('test/tool/bench_') and p.endswith('_test.dart'))
               or (p.startswith('tool/bench/') and not p.startswith('tool/bench/results/')) for p in changed), changed
    # 第一轮报告只允许追加，原有段落不可改写或删除。
    history = (ROOT / 'docs/METRIC_FIX_REPORT.md').read_bytes().split('## 第二轮：'.encode())[0].strip()
    prior_digest = read(OUT / 'before_hashes.json')['docs/METRIC_FIX_REPORT.md']
    # apply_patch可能规范换行；还原原有LF/CRLF及尾空行后必须匹配第一轮全文。
    normalized = history.replace(b'\r\n', b'\n')
    candidates = [normalized + b'\n' * count for count in range(4)]
    assert prior_digest in {hashlib.sha256(value).hexdigest()
                            for raw in candidates for value in [raw, raw.replace(b'\n', b'\r\n')]}
    result = {'relative_links_checked': links, 'broken_links': broken,
              'analysis_options_matches_guide': True, 'original_sha256_verified': len(provenance),
              'formal_identity_matches_MET': True, 'all_steady_windows_delivered': len(all_windows),
              'hard_guard_checks': p99_checks, 'cpu_estimates_verified': len(cpu),
              'process_cpu_measured': False, 'calibrated_floor_caps_verified': True,
              'measured_calibration_formula_verified': calibrated_count,
              'unstable_time_budgets_preserved': unstable_count,
              'initial_design_gaps': 14, 'scenes': dict(collections.Counter(s['status'] for s in scenes.values())),
              'changed_authorized_existing_paths': changed,
              'metric_report_original_sha256': prior_digest,
              'first_round_report_preserved_verified': True,
              'metric_report_preserved_history_normalized_sha256': hashlib.sha256(history.replace(b'\r\n', b'\n')).hexdigest(),
              'pubspec_sha256': {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest()
                                 for p in ['pubspec.yaml', 'tool/bench/pubspec.yaml']}}
    (OUT / 'selfcheck.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n',
                                      encoding='utf-8', newline='\n')
    print(json.dumps(result, ensure_ascii=False))


if __name__ == '__main__':
    main()
