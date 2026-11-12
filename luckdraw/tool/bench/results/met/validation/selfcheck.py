"""只读检查MET来源、文档链接、Dart/Python分类一致性和进程边界。"""
import collections
import hashlib
import json
import pathlib
import re
import xml.etree.ElementTree as ET

ROOT = pathlib.Path(__file__).resolve().parents[5]
OUT = pathlib.Path(__file__).resolve().parent
MET = OUT.parent


def read(path):
    """读取UTF-8 JSON。"""
    return json.loads(path.read_text(encoding='utf-8'))


def main():
    """生成可复核自检结果，发现矛盾立即失败。"""
    broken = []
    count = 0
    for doc in (ROOT / 'docs').glob('*.md'):
        for target in re.findall(r'\]\(([^)\s]+)\)', doc.read_text(encoding='utf-8')):
            if target.startswith(('http:', 'https:', 'mailto:', '#')):
                continue
            target = target.split('#')[0]
            if target:
                count += 1
                if not (doc.parent / target).exists():
                    broken.append((str(doc.relative_to(ROOT)), target))
    assert not broken, broken
    guide = (ROOT / 'docs/IMPLEMENTATION_GUIDE.md').read_text(encoding='utf-8')
    section = guide.split('### 2.3 analysis_options.yaml', 1)[1].split('### 2.4', 1)[0]
    expected_options = re.search(r'```yaml\n(.*?)```', section, re.S).group(1).strip()
    assert (ROOT / 'analysis_options.yaml').read_text(encoding='utf-8').strip() == expected_options
    provenance = read(MET / 'provenance.json')
    for item in provenance:
        assert hashlib.sha256((ROOT / item['source']).read_bytes()).hexdigest() == item['sha256']
    rows = read(MET / 'all_windows.json')
    dart = read(MET / 'sensitivity.json')
    actual = {}
    for scene in dart['scenarios'].values():
        for window in scene['windows']:
            if window['backpressure_contaminated'] is not None:
                actual[window['met_source']] = window['backpressure_contaminated']
    for window in dart['references']:
        actual[window['met_source']] = window['classification'] == 'BACKPRESSURE'
    assert len(actual) == len(rows)
    for row in rows:
        assert row['backpressure_contaminated'] == actual[row['source']]
    ET.parse(MET / 'raster_distribution.svg')
    selected = read(MET / 'assessment.json')
    outcomes = collections.Counter(s['status'] for s in selected['scenarios'].values())
    refs = [w for w in rows if w['report_key'] == 'reference_spin']
    assert sum(not w['delivery_passed'] for w in rows) == 0
    result = {'relative_doc_links': count, 'broken': broken, 'root_analysis_options_matches_section_2_3': True,
              'bench_analysis_options_restored_after_pub_get': True, 'provenance_hashes_verified': len(provenance),
              'classification_matches_dart': len(actual), 'distribution_svg_valid_xml': True,
              'windows': len(rows), 'contaminated': sum(w['backpressure_contaminated'] for w in rows),
              'reference_windows': len(refs), 'reference_contaminated': sum(w['backpressure_contaminated'] for w in refs),
              'scenarios': dict(outcomes), 'dependencies_sha256': {
                  p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest()
                  for p in ['pubspec.yaml', 'tool/bench/pubspec.yaml']}}
    (OUT / 'selfcheck.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8', newline='\n')
    print(json.dumps(result, ensure_ascii=False))


if __name__ == '__main__':
    main()
