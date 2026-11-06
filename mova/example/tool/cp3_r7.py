"""Blocking seventh-round headers campaign; commit every whole attempt immediately."""
from datetime import datetime
import hashlib
import json
import os
import shutil
import subprocess
import sys

import cp3_r5 as r5
import cp3_r2 as prev
from coverage_device import unlocked

ROOT, TOOL, SUMMARY = prev.ROOT, prev.TOOL, prev.SUMMARY
OUT = TOOL/'coverage_evidence'/('cp3-r7-'+datetime.now().strftime('%Y%m%d-%H%M%S'))
PATHS = ['example/tool/cp3_r7.py', 'example/tool/cp3_runtime.py', 'example/tool/coverage_build.py',
         'doc/plans/2026-11-05-cp3-results.md', 'doc/plans/2026-11-05-cp3-results.json']


def analyze(folder):
    a = r5.analyze(folder)
    raw = json.loads((folder/(folder.name+'-cp3-headers.json')).read_text(encoding='utf-8'))
    for path in ('pool-ready', 'pool-ready-cutover'):
        v = a[path]
        auth = [x['observations']['authorized'] for x in v['samples']]
        v['captureWaitMsEach'] = [x.get('captureWaitMs') for x in auth]
        v['successfulOver1000UpTo2000ms'] = sum(x.get('decoded') is True and
            1000 < x.get('captureWaitMs', 0) <= 2000 for x in auth)
        v['over2000ms'] = [x for x in auth if x.get('captureWaitMs', 0) > 2000]
    a['fixtureCompleted'] = raw.get('completed') is True
    a['sampleSetComplete'] = (a['fixtureCompleted'] and not raw.get('harness') and not raw.get('missing')
        and a['extract']['total'] == 60 and all(a[k]['total'] == a[k]['deniedTotal'] == 30
            for k in ('pool-ready', 'pool-ready-cutover')))
    return a


def save(s):
    data = json.loads(SUMMARY.with_suffix('.json').read_text(encoding='utf-8'))
    data['seventhRoundRevalidation'] = s
    SUMMARY.with_suffix('.json').write_text(json.dumps(data, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    old = SUMMARY.with_suffix('.md').read_text(encoding='utf-8').split('\n## 第七轮复验')[0]
    lines = ['', '## 第七轮复验', '',
        f"起点 `{s['head']}`；含 61903e73 对应的 383c56a1 判据修正（相关夹具文件 diff 为空）；本人执行，未转派。",
        f"STG-AL00 / {prev.SERIAL}；release APK SHA-256 `{s.get('apkSha256', '构建中')}`。",
        '开启 `CP3_HEADERS_READY=true` 与 `CP3_HEADERS_R4=true`；仅 headers，未运行 Windows 验证。',
        f"开始 {s['started']}；结束 {s.get('finished', '执行中')}；完整样本={s.get('complete', False)}。", '',
        '|尝试 / run-id|整批|PASS / FAIL / BLOCKED|完整样本|', '|---|---|---|---|']
    for row in s['attempts']:
        c = row['counts']
        lines.append(f"|{row['attempt']} / `{row['runId']}`|{row['status']}|{c.get('PASS',0)} / {c.get('FAIL',0)} / {c.get('BLOCKED',0)}|{row.get('analysis',{}).get('sampleSetComplete',False)}|")
        lines += ['', '|quality ID|结果|auto + 360p / 原生 path / 无头拒绝 / 新截图|', '|---|---|---|']
        for q in row.get('qualityChecks', []):
            lines.append(f"|{q['id']}|{q['status']}|{q['qualityAccepted']} / {q['pathAccepted']} / {q['deniedAccepted']} / {q['captureAccepted']}|")
        lines += ['', f"其余十条：{row.get('otherChecks')}。证据：`{row['evidence']}`；安装哈希匹配={row.get('installationHashMatches', False)}。", '', '```json', json.dumps(row.get('qualityChecks', []), ensure_ascii=False, indent=2), '```']
    lines += ['', '与第六轮对比：第六轮两批均 10 PASS / 5 FAIL，五条 quality 的直接失败项为旧 pool；当时未采集完整档位及选档 path。第七轮使用修正判据与新增原生选档回执，不反写第六轮 FAIL；各次结果见上表。', '',
        '结论：'+s.get('conclusion', '执行中')+'。', '',
        '仍未解决：旧原始截图/renderer future 不保证可读帧；抽帧内部 seek 重试无公开回执，不能以耗时推算命中；此前其他批次及人工项目维持历史结论，本轮局部结果不代表 CP3 整体验收通过。产品截图2秒契约不变。', '',
        '偏差：'+('；'.join(s['deviations']) or '无')+'。', '',
        '构建约束：`'+json.dumps(s.get('buildVerification',{}),ensure_ascii=False)+'`。', '',
        '恢复读回：`'+json.dumps(s.get('restoration',{}),ensure_ascii=False)+'`。', '',
        '恢复异常：'+s.get('restorationError','无')+'。', '',
        '逐批提交：'+', '.join(s['commits'])+'（当前提交自身 hash 见最终汇报）。', '',
        '停止原因：'+s.get('stopReason','执行中')+'。']
    SUMMARY.with_suffix('.md').write_text(old+'\n'.join(lines)+'\n', encoding='utf-8')
    (OUT/'state.json').write_text(json.dumps(s, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')


def quality_checks(folder):
    raw = json.loads((folder/(folder.name+'-cp3-headers.json')).read_text(encoding='utf-8'))
    checks = [r for r in raw['records'] if r.get('kind') == 'CHECK']
    result = []
    for r in checks:
        if '.quality.' not in r['id']: continue
        n = r['numbers']; o = n.get('qualityObservations', {})
        yes, no = o.get('authorized', {}), o.get('denied', {})
        qs = yes.get('qualities', [])
        good = [q for q in n.get('requests', []) if q.get('query','').endswith('-yes')]
        bad = [q for q in n.get('requests', []) if q.get('query','').endswith('-no')]
        result.append(dict(id=r['id'], status=r.get('status'), observations=o, requests=n.get('requests'),
            qualityAccepted=len(qs)==2 and qs[0].get('auto') is True and qs[1].get('auto') is False and qs[1].get('height')==360 and qs[1].get('label')=='360p' and qs[1].get('uri')==yes.get('expectedUri'),
            pathAccepted=bool(yes.get('expectedUri')) and yes.get('selectedPath')==yes.get('expectedUri') and bool(good) and all(q['status']==200 for q in good),
            deniedAccepted=no.get('qualities')==[] and n.get('negative') is False and bool(bad) and all(q['status']==403 for q in bad),
            captureAccepted=n.get('captureReady') is True and all(n.get('nativePaths',{}).get(k,{}).get('pass') is True for k in ('extract','pool-ready','pool-ready-cutover')),
            nativePaths={k:v.get('pass') for k,v in n.get('nativePaths',{}).items()}))
    other = [dict(id=r['id'],status=r.get('status')) for r in checks if '.quality.' not in r['id']]
    return result, other


def commit(s, label):
    save(s)
    prev.call(['git', 'add', '--', *PATHS], check=True)
    prev.call(['git', 'diff', '--cached', '--check'], check=True)
    staged = subprocess.check_output(['git', 'diff', '--cached', '--name-only', '--relative'], cwd=ROOT, text=True).splitlines()
    if set(staged)-set(PATHS):
        raise RuntimeError('Unexpected staged paths: '+repr(staged))
    prev.call(['git', '-c', 'maintenance.auto=false', '-c', 'gc.auto=0', 'commit', '-m',
        'test(mova): CP3 seventh round '+label+prev.SUFFIX], check=True)
    s['commits'].append(subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip())
    print('R7 COMMIT', s['commits'][-1], flush=True)


def restore(before):
    prev.adb('shell', 'settings', 'put', 'global', 'stay_on_while_plugged_in', before['power'])
    prev.adb('shell', 'cmd', 'media_session', 'volume', '--stream', '3', '--set', before['volume'])
    if prev.snapshot()['volume'] != before['volume']:
        prev.call([sys.executable, '-B', TOOL/'cp3_r3_restore_volume.py', OUT], check=True)
    for direction in ('reverse', 'forward'):
        def mappings(raw):
            return {p[-2]:p[-1] for line in raw.splitlines() if len(p := line.split()) == 3
                    and (direction == 'reverse' or p[0] == prev.SERIAL)}
        target = mappings(before[direction])
        current = mappings(prev.adb(direction, '--list'))
        for source in current.keys()-target.keys():
            prev.adb(direction, '--remove', source)
        for source, dest in target.items():
            if current.get(source) != dest:
                prev.adb(direction, source, dest)
    after = prev.snapshot()
    if before != after:
        raise RuntimeError('Restoration mismatch: '+repr(dict(before=before, after=after)))
    return dict(before=before, after=after, matches=True)


def main():
    global OUT
    resume = len(sys.argv) == 3 and sys.argv[1] == "--resume"
    if resume:
        OUT = __import__("pathlib").Path(sys.argv[2]).resolve()
    os.environ.update(MOVA_CP3_CAMPAIGN='1', MOVA_CP3_BUILD_MAX_ATTEMPTS='3', MOVA_CP3_HEADERS_R4='1', MOVA_CP3_HEADERS_READY='1',
        MOVA_MATRIX_SERIAL=prev.SERIAL, ANDROID_SERIAL=prev.SERIAL,
        ANDROID_SDK_ROOT='E:/sdk/android', ANDROID_HOME='E:/sdk/android', PYTHONDONTWRITEBYTECODE='1')
    OUT.mkdir(parents=True, exist_ok=resume)
    (ROOT/'example/.dart_tool/b09').mkdir(parents=True, exist_ok=True)
    s = dict(started=datetime.now().astimezone().isoformat(),
        head=subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
        attempts=[], commits=[], complete=False, deviations=['当前 HEAD 383c56a1；61903e73 对应夹具文件内容一致，未切分支或改动其他工作树。', '首次构建在内存门槛通过后 Dart allocation.cc 报 Out of memory；原识别器漏检该文本，已补齐，失败日志保留于 example/tool/coverage_evidence/cp3-r7-20261105-124500 与 example/tool/cp3-build-attempt-1.log；后续构建最多三次，合计最多三次重试。', '首次构建退出后的报告提交被脚本一处尾随空白阻止，已修正；当时无真机批次，设备设置读回一致。'])
    if resume:
        s = json.loads((OUT/"state.json").read_text(encoding="utf-8"))
        s.pop("finished", None)
        s.pop("restoration", None)
    before = prev.snapshot()
    s['initialSettings'] = before
    (OUT/'initial-settings.json').write_text(json.dumps(before), encoding='utf-8')
    try:
        if not resume:
            unlocked()
            argv = [sys.executable, '-B', TOOL/'coverage_build.py', 'lib/main_coverage_suite.dart', '--max-workers=2',
                '-Dorg.gradle.jvmargs=-Xms128m -Xmx1024m -XX:MaxMetaspaceSize=384m -XX:ReservedCodeCacheSize=96m -XX:TieredStopAtLevel=1 -XX:ActiveProcessorCount=2 -XX:+UseSerialGC -XX:HeapBaseMinAddress=0x100000000',
                '-Pkotlin.compiler.execution.strategy=in-process']
            print('R7 BUILD', OUT, flush=True)
            with (OUT/'build-console.log').open('w', encoding='utf-8') as log:
                prev.call(argv, stdout=log, stderr=subprocess.STDOUT, check=True)
            shutil.copy2(TOOL/'coverage_isolated_build.log', OUT/'build.log')
            apk = OUT/'cp3-r7-release.apk'
            shutil.copy2(ROOT/'example/build/app/outputs/flutter-apk/app-release.apk', apk)
            s['apkSha256'] = hashlib.sha256(apk.read_bytes()).hexdigest()
            s['apk'] = str(apk.relative_to(ROOT))
            build_text = (OUT/'build-console.log').read_text(encoding='utf-8')
            s['buildVerification'] = dict(dartDefines=['CP3_HEADERS_READY=true', 'CP3_HEADERS_R4=true'],
                memoryThresholdKiB=3670016, memoryPollSeconds=60, memoryWaitLimitMinutes=40,
                freePhysicalMemoryKiBReadings=[int(x.split(':')[-1]) for x in build_text.splitlines()
                    if x.startswith('CP3 FreePhysicalMemory KiB:')], maxWorkers=2,
                virtualMemoryRetries=1+build_text.count('CP3 virtual memory failure; retry'), priorBuildFreePhysicalMemoryKiB=5024336, priorBuildFailure='Dart allocation.cc: Out of memory', priorBuildEvidence='example/tool/coverage_evidence/cp3-r7-20261105-124500', onlyHeaders=True, windowsValidation=False)
            save(s)
        else:
            apk = ROOT/s["apk"]
            if hashlib.sha256(apk.read_bytes()).hexdigest() != s["apkSha256"]:
                raise RuntimeError("Resume APK hash mismatch")
        infrastructure_makeup = False
        for attempt in range(len(s["attempts"])+1, 4):
            if attempt == 3 and not infrastructure_makeup:
                break
            unlocked()
            run_id = 'cp3-headers-r7-'+datetime.now().strftime('%Y%m%d-%H%M%S')
            console = OUT/(run_id+'.console.log')
            print('R7 BEGIN', attempt, run_id, s['apkSha256'], flush=True)
            with console.open('w', encoding='utf-8') as log:
                code = prev.call([sys.executable, '-B', TOOL/'run_matrix.py', '--only', 'cp3-headers',
                    '--run-id', run_id, '--reuse-apk', apk, '--baseline',
                    ROOT/'doc/plans/2026-11-03-s00e-matrix-replay-r1030.json'], stdout=log, stderr=subprocess.STDOUT).returncode
            row = prev.summarize('cp3-headers', run_id, attempt, code, console)
            s['attempts'].append(row)
            try:
                folder = ROOT/row['evidence']
                row['analysis'] = a = analyze(folder)
                row['installationVerification'] = json.loads((folder/(folder.name+'-build.json')).read_text(encoding='utf-8'))
                row['installationHashMatches'] = (row['installationVerification']['sha256']['signed'] ==
                    row['installationVerification']['sha256']['device'] == s['apkSha256'])
                row['qualityChecks'], row['otherChecks'] = quality_checks(folder)
                a['sampleSetComplete'] = a['sampleSetComplete'] and len(row['qualityChecks']) == 5 and len(row['otherChecks']) == 10
                row['qualityAccepted'] = all(all(q[k] for k in ('qualityAccepted','pathAccepted','deniedAccepted','captureAccepted')) for q in row['qualityChecks'])
                row['newSignalAccepted'] = row['qualityAccepted'] and a['sampleSetComplete'] and row['installationHashMatches'] and all(
                    a[k]['accepted'] for k in ('pool-ready', 'pool-ready-cutover'))
            except Exception as error:
                row['analysisError'] = repr(error)
            complete_rows = [r for r in s['attempts'] if r.get('analysis', {}).get('sampleSetComplete')]
            if complete_rows:
                s['conclusion'] = ('修复有效，headers 整批通过' if all(r.get('newSignalAccepted') and r['status']=='PASS' for r in complete_rows)
                    else '复验未通过')+'（同时验收五条quality完整档位、选档path、403及普通/cutover各30次截图对照与其余十条）；所有完整批次及失败保留，非完整批次不拼接样本'
            else:
                s['conclusion'] = '仍待定：基础设施中断或证据缺失，尚无完整样本集'
            if not row.get('analysis', {}).get('sampleSetComplete'):
                row['classification'] = '基础设施中断/缺证据，未形成完整样本集'
                if attempt == 2:
                    infrastructure_makeup = True
                    s['deviations'].append('第二次整批未完成，按授权追加一次基础设施补跑；不拼接样本。')
            print('R7 END', row['status'], row.get('newSignalAccepted'), flush=True)
            commit(s, 'headers attempt '+str(attempt)+' evidence')
            if row['status'] == 'PASS' and row.get('newSignalAccepted'):
                break
        s['complete'] = any(r.get('analysis', {}).get('sampleSetComplete') for r in s['attempts'])
        s['stopReason'] = '限定批次已返回最终结果；完整样本集独立判定，失败与中断保留'
    except BaseException as error:
        s['stopReason'] = repr(error)
        raise
    finally:
        try:
            s['restoration'] = restore(before)
        except Exception as error:
            s['restorationError'] = repr(error)
        s['finished'] = datetime.now().astimezone().isoformat()
        commit(s, 'final results and device restoration')


if __name__ == '__main__':
    main()
