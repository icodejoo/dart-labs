"""PEND 只读自检：链接、配置、原始证据及产品/基线冻结身份。"""
import hashlib
import json
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parents[5]
OUT = pathlib.Path(__file__).resolve().parent


def read(path):
    """读取原始 JSON；不更新历史结果。"""
    return json.loads(path.read_text(encoding='utf-8'))


def main():
    """校验离线证据和文档，不调用设备或 Flutter。"""
    docs = list((ROOT / 'docs').glob('*.md')) + [ROOT / 'README.md', ROOT / 'README.zh-CN.md', ROOT / 'tool/bench/README.md']
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
    frozen = read(OUT / 'frozen_product.json')
    assert all(hashlib.sha256((ROOT / path).read_bytes()).hexdigest() == digest
               for path, digest in frozen.items())
    provenance = read(ROOT / 'tool/bench/results/met2/provenance.json')
    assert all(hashlib.sha256((ROOT / row['source']).read_bytes()).hexdigest() == row['sha256']
               for row in provenance)
    windows = read(ROOT / 'tool/bench/results/pend_offline/frames.json')
    assert len(windows) == 16
    assert len({(w['scenario'], w['run_id']) for w in windows}) == 16
    assert all(hashlib.sha256((ROOT / row['trace']).read_bytes()).hexdigest() == row['sha256']
               for row in windows)
    assert all(not w['unpaired_raster'] and all(f['ui_us'] <= 4000 for f in w['unpaired_ui_frames'])
               for w in windows)
    expected_counts = {'slot_raster': (5, 5), 'grid_steady': (10, 8),
                       'lotto_draw': (171, 24), 'lots_shaking': (0, 0)}
    for scene, counts in expected_counts.items():
        actual = tuple(sum(f['spike'] for w in windows if w['scenario'] == scene
                           and (not formal or w['formal']) for f in w['frames'])
                       for formal in (False, True))
        assert actual == counts, (scene, actual)
    new_files = ['tool/bench/pending_metrics.dart', 'tool/bench/cpu_sampler.dart',
                 'tool/bench/assess_pending.dart', 'tool/bench/pending_scene.dart',
                 'tool/bench/integration_test/pending_bench_test.dart',
                 'tool/bench/run_pending_device_checks.ps1', 'tool/bench/analyze_frames.py',
                 'test/tool/bench_pending_test.dart', 'docs/PERF_ROOTCAUSE_REPORT.md',
                 'tool/bench/fixtures/cpuinfo_android16.txt', 'tool/bench/fixtures/top_android16.txt',
                 'tool/bench/fixtures/top_tid.txt']
    assert all(b'\r\n' not in (ROOT / path).read_bytes() for path in new_files)
    result = {'relative_links_checked': links, 'broken_links': broken,
              'analysis_options_matches_guide': True, 'frozen_product_and_baseline_files': len(frozen),
              'historical_summary_sha256_verified': len(provenance),
              'raw_trace_sha256_verified': len(windows), 'all_and_formal_spikes': expected_counts,
              'new_text_files_lf': True, 'device_collection_run': False,
              'product_lib_changed': False, 'performance_passed_claimed': False}
    (OUT / 'selfcheck.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n',
                                      encoding='utf-8', newline='\n')
    print(json.dumps(result, ensure_ascii=False))


if __name__ == '__main__':
    main()
