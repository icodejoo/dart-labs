"""Blocking headers ready-signal revalidation; commit each whole-batch attempt."""
from datetime import datetime
import hashlib
import json
import os
import shutil
import statistics
import subprocess
import sys

import cp3_r4 as r4
import cp3_r2 as prev
from coverage_device import unlocked

ROOT, TOOL, SUMMARY = prev.ROOT, prev.TOOL, prev.SUMMARY
OUT = TOOL/'coverage_evidence'/('cp3-r5-'+datetime.now().strftime('%Y%m%d-%H%M%S'))
PATHS = ['example/tool/cp3_r5.py', 'example/tool/coverage_build.py',
         'doc/plans/2026-11-05-cp3-results.md', 'doc/plans/2026-11-05-cp3-results.json']


def distribution(values):
    values = sorted(values)
    return dict(count=len(values), min=min(values), median=statistics.median(values),
                p95=values[min(len(values)-1, int(len(values)*.95))], max=max(values)) if values else {}


def analyze(folder):
    data = json.loads((folder/(folder.name+'-cp3-headers.json')).read_text(encoding='utf-8'))
    result = r4.analyze(folder)
    for path in ('pool-ready', 'pool-ready-cutover'):
        samples = [s for r in data['records'] if r.get('kind') == 'CHECK' and '.quality.' in r.get('id', '')
                   for s in r['numbers']['nativePaths'][path]['samples']]
        auth = [s['observations']['authorized'] for s in samples]
        denied = [s['observations']['denied'] for s in samples]
        receipts = lambda suffix: [q for s in samples for q in s['requests'] if q['query'].endswith(suffix)]
        good, bad = receipts('-yes'), receipts('-no')
        v = dict(total=len(auth), null=sum(x.get('null') is True for x in auth),
                 decoded=sum(x.get('decoded') is True for x in auth),
                 paused=sum(x.get('paused') is True for x in auth),
                 missingCapture=sum('null' not in x for x in auth),
                 deniedTotal=len(denied), deniedDecoded=sum(x.get('decoded') is True for x in denied),
                 deniedRejected=sum(s['negative'] is False for s in samples),
                 authorizedReceiptCount=len(good), deniedReceiptCount=len(bad),
                 authorizedHttp200=bool(good) and all(q['status'] == 200 for q in good),
                 deniedHttp403=bool(bad) and all(q['status'] == 403 for q in bad),
                 passingSamples=sum(s['pass'] is True for s in samples),
                 captureWaitMs=distribution([x['captureWaitMs'] for x in auth if 'captureWaitMs' in x]),
                 captureStartAfterBindMs=distribution([x['captureAtMs']-x['bindReturnedMs'] for x in auth if 'captureAtMs' in x]),
                 over1000ms=[x for x in auth if x.get('captureWaitMs', 0) > 1000], samples=samples)
        v['accepted'] = (v['total'] == v['decoded'] == v['paused'] == v['passingSamples'] == v['deniedRejected'] == 30
                         and v['null'] == v['missingCapture'] == v['deniedDecoded'] == 0
                         and v['authorizedHttp200'] and v['deniedHttp403'])
        result[path] = v
    return result


def save(s):
    data = json.loads(SUMMARY.with_suffix('.json').read_text(encoding='utf-8'))
    data['fifthRoundRevalidation'] = s
    SUMMARY.with_suffix('.json').write_text(json.dumps(data, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    old = SUMMARY.with_suffix('.md').read_text(encoding='utf-8').split('\n## 第五轮复验')[0]
    lines = ['', '## 第五轮复验', '',
             f"起点 `{s['head']}`；STG-AL00 / {prev.SERIAL}；release APK SHA-256 `{s.get('apkSha256', '构建中')}`。",
             '构建开启 `CP3_HEADERS_READY=true` 与 `CP3_HEADERS_R4=true`；仅 headers 真机验证，未运行 Windows 验证。',
             f"完成={s.get('complete', False)}；开始 {s['started']}；结束 {s.get('finished', '执行中')}。", '',
             '|尝试 / run-id|批次|普通 null / 解码|cutover null / 解码|抽帧|',
             '|---|---|---|---|---|']
    for row in s['attempts']:
        a = row.get('analysis', {})
        p, c, e = (a.get(k, {}) for k in ('pool-ready', 'pool-ready-cutover', 'extract'))
        lines.append(f"|{row['attempt']} / `{row['runId']}`|{row['status']}|{p.get('null')}/{p.get('total')} / {p.get('decoded')}/{p.get('total')}|{c.get('null')}/{c.get('total')} / {c.get('decoded')}/{c.get('total')}|{e.get('success')}/{e.get('total')}|")
    lines += ['', '第四轮对比：原始直截 null=17/30，renderer future 后 null=8/30，额外等 100ms 后 null=0/30；第五轮新入口从 bind 返回立即调用，无额外 sleep 或截图外层重试，普通/cutover 分开统计。', '',
              '结论：'+s.get('conclusion', '执行中')+'。', '', '逐尝试统计（原始失败与拒绝鉴权对照保留）：', '', '```json',
              json.dumps([{k: v for k, v in row.items() if k != 'analysis'} | {'analysis': {k: {a: b for a, b in v.items() if a not in ('samples', 'firstSuccess', 'elapsedMs')} for k, v in row.get('analysis', {}).items()}}
                          for row in s['attempts']], ensure_ascii=False, indent=2), '```', '',
              '仍未解决：', '', '- 旧原始截图/renderer future 不保证截图就绪，新能力成功不升级旧信号契约。',
              '- 抽帧内部 seek 重试次数没有公开回执；耗时不是重试命中证据。',
              '- 前四轮其余未解决项保留；本轮局部验收不代表 CP3 整体验收通过。',
              '- 1 秒产品等待上限以既有单测为边界；真机调用总耗时含调度与返回开销，超过部分单列，不据此放宽上限。', '',
              '偏差：', ''] + ['- '+x for x in s['deviations']]
    if 'buildVerification' in s:
        lines += ['', '构建/执行约束核验：', '', '```json',
                  json.dumps(s['buildVerification'], ensure_ascii=False, indent=2), '```']
    if 'comparisonWithFourthRound' in s:
        lines += ['', '第四轮与第五轮完整首批对比：', '', '```json',
                  json.dumps(s['comparisonWithFourthRound'], ensure_ascii=False, indent=2), '```']
    lines += ['', '恢复读回：`'+json.dumps(s.get('restoration', {}), ensure_ascii=False)+'`。', '',
              '已提交：'+', '.join(s['commits'])+'（当前提交自身 hash 见最终汇报）。', '',
              '停止原因：'+s.get('stopReason', '无')+'。']
    SUMMARY.with_suffix('.md').write_text(old+'\n'.join(lines)+'\n', encoding='utf-8')
    (OUT/'state.json').write_text(json.dumps(s, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')


def commit(s, label):
    save(s)
    prev.call(['git', 'add', '--', *PATHS], check=True)
    prev.call(['git', 'diff', '--cached', '--check'], check=True)
    prev.call(['git', '-c', 'maintenance.auto=false', '-c', 'gc.auto=0', 'commit', '-m',
               'test(mova): CP3 fifth round '+label+prev.SUFFIX], check=True)
    s['commits'].append(subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip())
    print('R5 COMMIT', s['commits'][-1], flush=True)


def main():
    os.environ.update(MOVA_CP3_CAMPAIGN='1', MOVA_CP3_HEADERS_R4='1', MOVA_CP3_HEADERS_READY='1',
                      MOVA_MATRIX_SERIAL=prev.SERIAL, ANDROID_SERIAL=prev.SERIAL,
                      ANDROID_SDK_ROOT='E:/sdk/android', ANDROID_HOME='E:/sdk/android', PYTHONDONTWRITEBYTECODE='1')
    OUT.mkdir(parents=True)
    (ROOT/'example/.dart_tool/b09').mkdir(parents=True, exist_ok=True)
    s = dict(started=datetime.now().astimezone().isoformat(), head=subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
             attempts=[], commits=[], complete=False, deviations=['失败时仅整批重试一次；各次原始失败保留，不追加 sleep 覆盖新信号结果。'])
    before = prev.snapshot()
    s['initialSettings'] = before
    (OUT/'initial-settings.json').write_text(json.dumps(before), encoding='utf-8')
    try:
        unlocked()
        argv = [sys.executable, '-B', TOOL/'coverage_build.py', 'lib/main_coverage_suite.dart', '--max-workers=2',
                '-Dorg.gradle.jvmargs=-Xms128m -Xmx1024m -XX:MaxMetaspaceSize=384m -XX:ReservedCodeCacheSize=96m -XX:TieredStopAtLevel=1 -XX:ActiveProcessorCount=2 -XX:+UseSerialGC -XX:HeapBaseMinAddress=0x100000000',
                '-Pkotlin.compiler.execution.strategy=in-process']
        print('R5 BUILD', OUT, flush=True)
        with (OUT/'build-console.log').open('w', encoding='utf-8') as log:
            prev.call(argv, stdout=log, stderr=subprocess.STDOUT, check=True)
        shutil.copy2(TOOL/'coverage_isolated_build.log', OUT/'build.log')
        apk = OUT/'cp3-r5-release.apk'
        shutil.copy2(ROOT/'example/build/app/outputs/flutter-apk/app-release.apk', apk)
        s['apkSha256'] = hashlib.sha256(apk.read_bytes()).hexdigest()
        s['apk'] = str(apk.relative_to(ROOT))
        save(s)
        for attempt in (1, 2):
            unlocked()
            run_id = 'cp3-headers-r5-'+datetime.now().strftime('%Y%m%d-%H%M%S')
            console = OUT/(run_id+'.console.log')
            print('R5 BEGIN', attempt, run_id, s['apkSha256'], flush=True)
            with console.open('w', encoding='utf-8') as log:
                code = prev.call([sys.executable, '-B', TOOL/'run_matrix.py', '--only', 'cp3-headers', '--run-id', run_id,
                                  '--reuse-apk', apk, '--baseline', ROOT/'doc/plans/2026-11-03-s00e-matrix-replay-r1030.json'],
                                 stdout=log, stderr=subprocess.STDOUT).returncode
            row = prev.summarize('cp3-headers', run_id, attempt, code, console)
            s['attempts'].append(row)
            try:
                folder = ROOT/row['evidence']
                row['analysis'] = a = analyze(folder)
                row['installationVerification'] = json.loads((folder/(folder.name+'-build.json')).read_text(encoding='utf-8'))
                row['newSignalAccepted'] = all(a[k]['accepted'] for k in ('pool-ready', 'pool-ready-cutover'))
                s['conclusion'] = ('修复有效：普通与cutover新截图入口各30/30可解码、null=0，暂停及拒绝403对照通过' if row['newSignalAccepted'] else
                                   '修复无效：本次新入口未满足每侧30/30可解码、null=0及暂停/403对照验收，详见保留样本')
                s['conclusion'] += '；仅判定可选截图入口，旧路径及CP3整体结论保留'
            except Exception as error:
                row['analysisError'] = repr(error)
                s['conclusion'] = '仍待定：本次缺少完整新信号证据'
            print('R5 END', row['status'], row.get('newSignalAccepted'), flush=True)
            commit(s, 'headers attempt '+str(attempt)+' evidence')
            if row['status'] == 'PASS' and row.get('newSignalAccepted'):
                break
        s['complete'] = True
    except BaseException as error:
        s['stopReason'] = repr(error)
        raise
    finally:
        try:
            prev.adb('shell', 'settings', 'put', 'global', 'stay_on_while_plugged_in', before['power'])
            prev.adb('shell', 'cmd', 'media_session', 'volume', '--stream', '3', '--set', before['volume'])
            if prev.snapshot()['volume'] != before['volume']:
                prev.call([sys.executable, '-B', TOOL/'cp3_r3_restore_volume.py', OUT], check=True)
            after = prev.snapshot()
            s['restoration'] = dict(before=before, after=after, matches=before == after)
            if before != after:
                raise RuntimeError('Device settings/mappings restoration mismatch')
        except Exception as error:
            s['restorationError'] = repr(error)
        s['finished'] = datetime.now().astimezone().isoformat()
        commit(s, 'final results and device restoration')


if __name__ == '__main__':
    main()
