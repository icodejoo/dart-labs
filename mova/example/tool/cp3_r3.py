"""Blocking, narrowly scoped third APK revalidation; commit every attempt."""
from collections import Counter
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import zipfile

import cp3_r2 as previous
from cp0_device_guard import wait_online

ROOT, TOOL, SUMMARY = previous.ROOT, previous.TOOL, previous.SUMMARY
SERIAL = previous.SERIAL
PLAN = [('subtitles', 'cp3-r2-subtitles'), ('headers', 'cp3-headers'),
        ('receipt', 'cp3-r2-receipt'), ('pool', 'cp3-r2-pool'),
        ('extract-extra1', 'cp3-headers'), ('extract-extra2', 'cp3-headers')]
OUT = TOOL/'coverage_evidence'/('cp3-r3-'+datetime.now().strftime('%Y%m%d-%H%M%S'))
UNRESOLVED = [
    '字幕 PNG 及 sub-text/track-list/position 是自动证据；最终画面及听感仍需人工。',
    'pool/audioOnly 没有 CP0 同源同翻页数冷暖配对多轮和批准硬线；原生实例归属不可读时记未知，资源计数全绿不证明无泄漏/耗电改善。',
    '抽帧空帧 API 不暴露隐藏播放器 duration/seek/screenshot 阶段；若复现仍需实例/token 时间线及响应体校验。B07 精确目标帧/原生落点不在本批自动关闭范围。',
    'receipt 仅 basic/basic-cutover/abr 三命令；Seeked landingVerified=false 不代替 F3 原生稳定落点验收。',
    'CP1 fallback/7b 历史根因、亮度/弹幕硬线、Windows CP0 配对及 CP3 其他历史 FAIL/BLOCKED 未在限定清单重跑，原结论保留。',
]


def call(argv, **kwargs):
    return subprocess.run(list(map(str, argv)), cwd=ROOT,
                          creationflags=subprocess.CREATE_NO_WINDOW, **kwargs)


def write(state):
    data = json.loads(SUMMARY.with_suffix('.json').read_text(encoding='utf-8'))
    data['thirdRoundRevalidation'] = state
    SUMMARY.with_suffix('.json').write_text(json.dumps(data, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    original = SUMMARY.with_suffix('.md').read_text(encoding='utf-8').split('\n## 第三轮复验')[0]
    lines = ['', '## 第三轮复验', '',
             f"起点 `{state['head']}`；设备 STG-AL00 / {SERIAL}；同一个新 release APK SHA-256 `{state['apkSha256']}`。",
             f"开始 {state['started']}；完成={state.get('complete', False)}。只跑 remaining-triage 新 APK 清单，额外两轮 headers 收集抽帧首试诊断。", '',
             '|批次/尝试|第三轮|CHECK PASS/FAIL/BLOCKED|与第二轮对比|证据目录|', '|---|---|---|---|---|']
    for row in state['attempts']:
        c = row['counts']
        lines.append(f"|{row['label']}/{row['attempt']}|{row['status']}|{c.get('PASS',0)}/{c.get('FAIL',0)}/{c.get('BLOCKED',0)}|{row['comparison']}|`{row['evidence']}`|")
    lines += ['', '逐批证据与定性：', '']
    for row in state['attempts']:
        lines += [f"- `{row['runId']}`：{row['classification']}；疑似位置 `{row['suspectedLocations']}`。",
                  '  失败/缺证据：`'+json.dumps(dict(failures=row['failures'], errors=row['errors']), ensure_ascii=False)+'`。',
                  '  专项观测：`'+json.dumps(row.get('observations', {}), ensure_ascii=False)+'`。']
    lines += ['', '仍未解决/缺证据及需人工项：', ''] + ['- '+s for s in UNRESOLVED]
    lines += ['', '偏差：', ''] + ['- '+s for s in state['deviations']]
    lines += ['', '恢复原生读回：`'+json.dumps(state.get('restoration', {}), ensure_ascii=False)+'`。',
              '', '逐批提交（自身 hash 在后续提交/最终汇报）：'+', '.join(state['commits'])+'。',
              '', f"未完成：{state['unfinished']}；原因：{state.get('stopReason','执行中')}。"]
    SUMMARY.with_suffix('.md').write_text(original+'\n'.join(lines)+'\n', encoding='utf-8')
    (OUT/'state.json').write_text(json.dumps(state, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')


def commit(state, label):
    write(state)
    paths = ['example/tool/cp3_r3.py', 'example/tool/coverage_device.py',
             'doc/plans/2026-11-05-cp3-results.md', 'doc/plans/2026-11-05-cp3-results.json']
    call(['git', 'add', '--', *paths], check=True)
    call(['git', 'diff', '--cached', '--check'], check=True)
    call(['git', '-c', 'maintenance.auto=false', '-c', 'gc.auto=0', 'commit', '-m',
          'test(mova): CP3 third round '+label+previous.SUFFIX], check=True)
    sha = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    state['commits'].append(sha)
    print('R3 COMMIT', sha, label, flush=True)


def observations(row):
    folder = ROOT/row['evidence']
    records = []
    for path in folder.glob('*.json'):
        try:
            data = json.loads(path.read_text(encoding='utf-8'))
        except (ValueError, OSError):
            continue
        if not isinstance(data, dict) or 'records' not in data:
            continue
        rs = data['records']
        start = max((i for i, r in enumerate(rs) if r.get('kind') == 'BEGIN'), default=0)
        records += rs[start:]
    wanted = ['SUBTITLE_SHOT', 'RESOURCE_SAMPLE']
    result = {kind: [r for r in records if r.get('kind') == kind] for kind in wanted}
    result['nativeSnapshots'] = [str(p.relative_to(ROOT)) for p in folder.glob('*.native.json')]
    result['headerChecks'] = [dict(id=r['id'], nativePaths=r.get('numbers', {}).get('nativePaths'))
                              for r in records if r.get('kind') == 'CHECK' and
                              r.get('id', '').startswith('CP3.headers.quality.')]
    result['receiptChecks'] = dict(Counter(r.get('id') for r in records if r.get('kind') == 'CHECK' and 'receipt' in r.get('id', '')))
    return {k: v for k, v in result.items() if v}


def main():
    os.environ.update(MOVA_CP3_CAMPAIGN='1', MOVA_MATRIX_SERIAL=SERIAL, ANDROID_SERIAL=SERIAL,
                      ANDROID_SDK_ROOT='E:/sdk/android', ANDROID_HOME='E:/sdk/android', PYTHONDONTWRITEBYTECODE='1')
    OUT.mkdir(parents=True)
    (ROOT/'example/.dart_tool/b09').mkdir(parents=True, exist_ok=True)
    apk = OUT/'cp3-r3-release.apk'
    shutil.copy2(ROOT/'example/build/app/outputs/flutter-apk/app-release.apk', apk)
    shutil.copy2(TOOL/'coverage_isolated_build.log', OUT/'build.log')
    with zipfile.ZipFile(apk) as z:
        native = z.read('lib/arm64-v8a/libmpv.so')
        if len(native) < 1024 or native.startswith(b'version https://git-lfs'):
            raise RuntimeError('APK native LFS pointer')
    state = dict(started=datetime.now().astimezone().isoformat(),
                 head=subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
                 apk=str(apk.relative_to(ROOT)), apkSha256=hashlib.sha256(apk.read_bytes()).hexdigest(),
                 attempts=[], commits=[], unfinished=[label for label, _ in PLAN], complete=False,
                 deviations=['首次构建 PowerShell 拆分 -Pkotlin.compiler.execution.strategy 参数，构建任务查找失败；保留 cp3-r3-build-argument-failure.log，改用 Python 参数数组成功重跑，不计虚拟内存重试。',
                             '资源 host dumps 在 RESOURCE_SAMPLE 被轮询读到后依次采集，保存各命令起止时间/返回码/原文；快速阶段不声称严格同时或按实例回收。',
                             'headers 每批保持原 5 轮和原判据，额外两批收集首试诊断；不在抽帧调用内重试。',
                             '每批 --reuse-apk 会重装并拉回同一 APK 核对 SHA-256；没有重新构建。'])
    before = previous.snapshot()
    state['initialSettings'] = before
    (OUT/'initial-settings.json').write_text(json.dumps(before, indent=2), encoding='utf-8')
    try:
        for label, batch in PLAN:
            for attempt in (1, 2):
                wait_online(SERIAL)
                run_id = 'cp3-'+label+'-r3-'+datetime.now().strftime('%Y%m%d-%H%M%S')
                console = OUT/(run_id+'.console.log')
                print('R3 BEGIN', label, attempt, run_id, flush=True)
                with console.open('w', encoding='utf-8') as log:
                    code = call([sys.executable, '-B', TOOL/'run_matrix.py', '--only', batch,
                                 '--run-id', run_id, '--reuse-apk', apk, '--baseline',
                                 ROOT/'doc/plans/2026-11-03-s00e-matrix-replay-r1030.json'],
                                stdout=log, stderr=subprocess.STDOUT).returncode
                row = previous.summarize(batch, run_id, attempt, code, console)
                row.update(label=label, observations={})
                row['observations'] = observations(row)
                old = {'subtitles':'BLOCKED：SRT 未打包，0/4 验收',
                       'headers':'FAIL：池预热 0/5；抽帧 4/5→5/5',
                       'receipt':'FAIL：208 PASS/14 FAIL',
                       'pool':'BLOCKED：7 条资源计数缺失'}.get(label, '前两轮 headers 首试诊断')
                row['comparison'] = old+' → 自动检查 '+row['status']
                if batch == 'cp3-r2-pool':
                    row['automaticStatus'] = row['status']
                    if row['status'] == 'PASS': row['status'] = 'BLOCKED'
                    row['classification'] = '夹具计数与逻辑释放见自动结果；资源验收缺 CP0 配对多轮/批准硬线/原生实例归属，未证产品泄漏'
                    row['suspectedLocations'] = 'lib/src/core/engine_pool.dart; example/lib/verify_auto/s00d_resources.dart'
                elif batch == 'cp3-r2-subtitles':
                    row['classification'] = 'SRT 打包夹具修正后四格式原生自动验收；人工画面复核另列'
                    row['suspectedLocations'] = 'example/pubspec.yaml; example/lib/verify_auto/coverage_new.dart:subtitles'
                elif batch == 'cp3-headers':
                    row['classification'] = '池 ready 夹具改为真实暂停截图+媒体状态；抽帧首试保留 outcome/bytes/elapsed，失败仍待内部阶段定因'
                    row['suspectedLocations'] = 'lib/src/core/engine_pool.dart:_openBinding; lib/src/platform_impl/mpv_extractor_impl.dart:_extractNow'
                else:
                    row['classification'] = '普通引擎同步状态事件修复及 Seeked 跨流夹具修正后真机复验，落点不由 receipt 证明'
                    row['suspectedLocations'] = 'lib/src/core/engine.dart; example/lib/verify_auto/s00d_receipt.dart'
                state['attempts'].append(row)
                print('R3 END', label, row['status'], row['counts'], 'errors', row['errors'], flush=True)
                commit(state, label+' attempt '+str(attempt)+' evidence')
                if row.get('automaticStatus', row['status']) == 'PASS': break
            state['unfinished'].remove(label)
        state.update(complete=True, stopReason='限定批次及额外抽帧两轮均已返回最终结果，失败整批至多重试一次。')
    except BaseException as error:
        state['stopReason'] = repr(error)
        raise
    finally:
        after = previous.snapshot()
        state['restoration'] = dict(before=before, after=after, matches=before == after)
        commit(state, 'final results and restoration')


if __name__ == '__main__':
    main()
