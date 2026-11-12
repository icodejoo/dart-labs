"""核对本次文件身份、时间、完整原始响应及交付，不访问手机。"""
import datetime
import hashlib
import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[5]
OUT = pathlib.Path(__file__).resolve().parent.parent


def load(path):
    """读取 JSON。"""
    return json.loads(path.read_text(encoding='utf-8-sig'))


def main():
    """任何错设备、混样、旧报告或零fps都拒绝验收。"""
    audit = load(OUT / 'audit.json')
    session = audit['session']
    started = datetime.datetime.fromisoformat(session['started_at'].replace('Z', '+00:00'))
    assert session['model'] == 'V2417' and session['android'] == '16'
    assert session['serial'] == '10AE9K17UE0011S'
    assert session['binary_sha256'].lower() == load(OUT / 'validation/apk.json')['sha256']
    assert len(audit['scenes']) == 13
    summaries = []
    raw_responses = 0
    for scene, attempts in audit['scenes'].items():
        assert 3 <= len(attempts) <= 5, scene
        for attempt in attempts:
            assert attempt['binary_sha256'] == session['binary_sha256']
            start = datetime.datetime.fromisoformat(attempt['started_at'].replace('Z', '+00:00'))
            assert start >= started
            directory = OUT / attempt['directory']
            assert directory.is_dir()
            assert (directory / 'stdout.log').is_file()
            assert (directory / 'stderr.log').is_file()
            if 'device_metrics' in attempt:
                assert attempt['device_metrics']['fps'] > 0
                assert attempt['device_metrics']['frame_count'] > 0
                raw_responses += 1
            for file in directory.glob('*.timeline_summary.json'):
                row = load(file)
                assert row['device_model'] == 'V2417' and row['device_serial'] == session['serial']
                recorded = datetime.datetime.fromisoformat(row['recorded_at'].replace('Z', '+00:00'))
                assert recorded >= start
                assert datetime.datetime.fromtimestamp(file.stat().st_mtime, datetime.timezone.utc) >= start
                assert row['fps'] > 0
                assert row['frame_count'] > 0
                assert file.with_name(file.name.replace('.timeline_summary.json', '.timeline.json')).is_file()
                summaries.append(str(file.relative_to(OUT)).replace('\\', '/'))
    for name in ['assessment.json', 'frame_assessment.json', 'REPORT.md', 'audit.json']:
        file = OUT / name
        assert file.is_file()
        assert datetime.datetime.fromtimestamp(file.stat().st_mtime, datetime.timezone.utc) >= started
    for row in audit['provenance']:
        file = OUT / row['path']
        assert hashlib.sha256(file.read_bytes()).hexdigest() == row['sha256'], file
    original = load(OUT / 'validation/lib.sha256.json')
    changed = [name for name, digest in original.items()
               if hashlib.sha256((ROOT / name).read_bytes()).hexdigest() != digest]
    assert not changed, changed
    result = {'device': session['model'], 'serial': session['serial'],
              'attempts': sum(map(len, audit['scenes'].values())),
              'project_attempts': {key: len(rows) for key, rows in audit['scenes'].items()},
              'driver_valid_rounds': {key: sum(r['valid'] for r in rows) for key, rows in audit['scenes'].items()},
              'fresh_summaries': len(summaries), 'raw_response_windows': raw_responses,
              'zero_fps_rounds': 0, 'lib_changed': changed, 'provenance_checked': len(audit['provenance'])}
    (OUT / 'validation/evidence_check.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n',
                                                       encoding='utf-8', newline='\n')
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
