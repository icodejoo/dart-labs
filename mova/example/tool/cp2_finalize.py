"""Summarize actual CP2 attempts without treating missing evidence as PASS."""
import argparse
from collections import Counter
from datetime import datetime
import json
from pathlib import Path
import re
import subprocess

from cp2_resume import COUNTS, E
from coverage_cp2 import VARIANTS
from cp2_alias import ALIASES
import run_matrix as matrix

ROOT = matrix.ROOT
SERIAL = '7NQBB23606003715'


def read(path):
    return json.loads(Path(path).read_text(encoding='utf-8'))


def write(path, data):
    Path(path).write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding='utf-8')


def restore(stage0):
    """Restore the session's original state, removing only CP2-owned mappings."""
    original = read(Path(stage0['evidence']) / (f"matrix-{stage0['run_id']}-restore.json"))
    commands = []

    def adb(*args):
        argv = ['adb', '-s', SERIAL, *map(str, args)]
        proc = subprocess.run(argv, capture_output=True, timeout=60)
        result = dict(argv=argv, exit=proc.returncode, stdout=proc.stdout.decode('utf-8', errors='replace'),
                      stderr=proc.stderr.decode('utf-8', errors='replace'))
        commands.append(result)
        if proc.returncode:
            raise RuntimeError(result)
        return result['stdout']

    def snapshot():
        volume = adb('shell', 'cmd', 'media_session', 'volume', '--stream', '3', '--get')
        match = re.search(r'volume is (\d+)', volume)
        if not match:
            raise RuntimeError('media volume unreadable')
        mappings = dict(reverse={}, forward={})
        for direction in mappings:
            for line in adb(direction, '--list').splitlines():
                parts = line.split()
                if len(parts) == 3 and (direction == 'reverse' or parts[0] == SERIAL):
                    mappings[direction][parts[1]] = parts[2]
        return dict(power=adb('shell', 'settings', 'get', 'global', 'stay_on_while_plugged_in').strip(),
                    volume=match[1], mappings=mappings)

    result = dict(original=original, status='FAIL')
    try:
        result['before'] = snapshot()
        adb('shell', 'am', 'force-stop', matrix.PACKAGE)
        adb('shell', 'cmd', 'media_session', 'volume', '--stream', '3', '--set', original['volume'])
        if original['power'] == 'null':
            adb('shell', 'settings', 'delete', 'global', 'stay_on_while_plugged_in')
        else:
            adb('shell', 'settings', 'put', 'global', 'stay_on_while_plugged_in', original['power'])
        owned = {'reverse': {18080, 18081, 18082, 18190, 18192, 18194}, 'forward': {18083, 18087}}
        for direction, ports in owned.items():
            for port in ports:
                key = f'tcp:{port}'
                previous = original['mappings'][direction].get(key)
                current = result['before']['mappings'][direction].get(key)
                if previous and previous != current:
                    adb(direction, key, previous)
                elif not previous and current:
                    adb(direction, '--remove', key)
        result['after'] = snapshot()
        result['status'] = 'VERIFIED' if result['after'] == original else 'FAIL'
    except Exception as error:
        result['error'] = repr(error)
    result['commands'] = commands
    write(E / 'cp2-resume-restored.json', result)
    return result


def diagnosis(scene, check):
    n = check.get('numbers') or {}
    if scene == 'bgowner' and '.view.' in check['id']:
        return dict(classification='FIXTURE', symptom='MovaView(source:null) 未创建渲染面与自动暂停守卫；后台仍推进。',
                    fixture='example/lib/verify_auto/cp2_bgowner_auto.dart', libSuspect=None)
    if scene == 'adpaths':
        return dict(classification='FIXTURE_AND_PRODUCT_SUSPECT' if '.mid.' in check['id'] and abs(n.get('resumeErrorMs') or 0) > 500 else 'FIXTURE',
                    symptom=f"广告回调 kind 覆盖记录类别 AD，ads={len(n.get('ads', []))}；resumeErrorMs={n.get('resumeErrorMs')}；epochs={n.get('epochs')}。",
                    fixture='example/lib/verify_auto/cp2_common.dart: cp2AdEvent',
                    libSuspect='lib/src/core/session/session.dart: _contentResumeAt / _onProgress / _playContent' if '.mid.' in check['id'] else None)
    if scene == 'playlist3':
        return dict(classification='FIXTURE', symptom=f"contentEnded={n.get('contentEnded')}；下一集 pre.started 早于 currentIndex 更新，夹具归入上一集。需按广告 source 归属。",
                    fixture='example/lib/verify_auto/cp2_playlist3_auto.dart', libSuspect=None)
    if scene == 'pod2':
        return dict(classification='FIXTURE_RESOURCE_CONTAMINATION_PRODUCT_UNRESOLVED', symptom=f"广告2 path/首帧可用但 epoch1={n.get('epoch1')}、epoch2={n.get('epoch2')}，未按要求递增；同批有OpenSLES/file cache/decoder初始化失败，注入内核未释放，需先排除夹具资源耗尽。",
                    fixture='example/lib/verify_auto/cp2_common.dart: cp2Engine缺ownsKernel:true', libSuspect='仅待隔离：lib/src/core/session/session.dart: _playAd / _resumeAfterAd；lib/src/core/cutover/cutover_engine.dart: prepare / commit')
    if scene == 'rate':
        valid = 'settled1x=true' in str(n.get('sourceVerdict'))
        return dict(classification='PRODUCT_SUSPECT' if valid else 'UNRESOLVED_FIXTURE_OR_PRODUCT', symptom=str(n.get('sourceVerdict')),
                    fixture=None if valid else 'example/lib/main_review_fixes_verify2.dart: _v13（sourceTitle门控的页面rate样本，未采到不等于原生speed错误）',
                    libSuspect='lib/src/core/session/session.dart: playAdNow / _contentRate / 倍速恢复；lib/src/core/cutover/cutover_engine.dart: setRate / commit')
    if scene == 'warmmute':
        return dict(classification='FIXTURE_RESOURCE_CONTAMINATION_PRODUCT_UNRESOLVED', symptom=str(n.get('sourceVerdict')) + '；同页有SL_RESULT_MEMORY_FAILURE，注入内核未移交所有权。',
                    fixture='example/lib/main_q13_mute_verify.dart: _newRig / _disposeRig',
                    libSuspect='仅待排除夹具后检查：lib/src/core/cutover/cutover_engine.dart / lib/src/core/keep_alive；未证实产品静音缺陷')
    return dict(classification='PRODUCT_SUSPECT', symptom=str(n.get('sourceVerdict') or '正式 CHECK 断言失败，见原始 numbers'),
                fixture=None, libSuspect='待原生证据定位；不凭 CHECK 名称确定根因')


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--restore', action='store_true')
    args = p.parse_args()
    stage0 = read(E / 'cp2-stage0.json')
    stage1 = read(E / 'cp2-stage1.json')
    resumed = read(E / 'cp2-resume.json')
    previous = read(Path(stage0['sessionEvidence']) / 'previous-results.json')
    commit_lines = subprocess.check_output(['git', 'log', '--reverse', '--format=%H%x09%s', 'cc4c1a37..HEAD'], cwd=ROOT, text=True).splitlines()
    commits = [dict(hash=line.split('\t', 1)[0], subject=line.split('\t', 1)[1]) for line in commit_lines]
    batch_commits = {}
    for c in commits:
        m = re.fullmatch(r'test\(mova\): CP2 (\S+) 续跑证据', c['subject'])
        if m:
            batch_commits.setdefault('cp2-' + m[1], []).append(c['hash'])
    restoration = restore(stage0) if args.restore else read(E / 'cp2-resume-restored.json') if (E / 'cp2-resume-restored.json').exists() else dict(status='PENDING')
    attempts = []
    per_id = {}
    failures = []
    legacy_findings = []
    for attempt in [*stage1['batches'], *resumed['attempts']]:
        scene = attempt['batch'].removeprefix('cp2-')
        run_id = attempt['run_id']
        raw_path = E / ('matrix-' + run_id) / (f'matrix-{run_id}-cp2-{scene}.json')
        original_raw_path = raw_path
        recovered_path = raw_path.with_suffix('.recovered.json')
        if recovered_path.exists():
            raw_path = recovered_path
        raw = read(raw_path) if raw_path.exists() else {}
        variant_indices = Counter()
        for source in raw.get('sourceResults', []):
            ident = f"CP2.{scene}.{source['variant']}.{variant_indices[source['variant']]}"
            variant_indices[source['variant']] += 1
            finding = dict(id=ident, run_id=run_id, status=source['status'], detail=source['detail'],
                           evidence=str(raw_path.relative_to(ROOT)), qualifiedAsFormalCheck=False)
            if source['status'] == 'FAIL':
                finding.update(diagnosis(scene, dict(id=ident, numbers=dict(sourceVerdict=source['detail']))))
            legacy_findings.append(finding)
        checks = [r for r in raw.get('records', []) if r.get('kind') == 'CHECK' and r.get('id', '').startswith('CP2.' + scene + '.') and not r['id'].endswith('.harness')]
        count = Counter(r.get('status') for r in checks)
        counts = {s: count[s] for s in ('PASS', 'FAIL', 'BLOCKED')}
        counts['BLOCKED'] += max(0, COUNTS[scene] - len(checks))
        row = dict(batch=attempt['batch'], run_id=run_id, planned=COUNTS[scene], executed=len(checks), counts=counts,
                   status='FAIL' if counts['FAIL'] else 'PASS' if counts['PASS'] == COUNTS[scene] and attempt.get('kind') == 'OK' else 'BLOCKED',
                   kind=attempt.get('kind'), evidence=attempt['evidence'], rawResult=str(raw_path.relative_to(ROOT)),
                   report=attempt.get('report'), harness=raw.get('harness', []), missing=raw.get('missing', []), memory=attempt.get('memory'))
        if raw.get('evidenceRecovery'):
            row.update(evidenceRecovery=True, originalRawResult=str(original_raw_path.relative_to(ROOT)))
        row['commit'] = batch_commits.get(attempt['batch'], []).pop(0) if '-resume-' in run_id and batch_commits.get(attempt['batch']) else '00bd194d'
        attempts.append(row)
        for c in checks:
            observation = dict(status=c['status'], run_id=run_id, evidence=row['rawResult'], numbers=c.get('numbers'))
            per_id.setdefault(c['id'], []).append(observation)
            if c['status'] == 'FAIL':
                failures.append(dict(id=c['id'], run_id=run_id, evidence=row['rawResult'], **diagnosis(scene, c)))
    partial_rate = E / 'matrix-cp2-rate-20261104-172603/matrix-cp2-rate-20261104-172603-cp2-rate.commands.log'
    if partial_rate.exists():
        for variant, index, status, detail in re.findall(r'RESULT\|(V13[ab])\|run(\d+)\|(PASS|FAIL)\|([^\r\n]*)', partial_rate.read_text(encoding='utf-8', errors='replace')):
            ident = f'CP2.rate.{variant}.{int(index)-1}'
            finding = dict(id=ident, run_id='cp2-rate-20261104-172603', status=status, detail=detail,
                           evidence=str(partial_rate.relative_to(ROOT)), qualifiedAsFormalCheck=False)
            if status == 'FAIL':
                finding.update(diagnosis('rate', dict(id=ident, numbers=dict(sourceVerdict=detail))))
            legacy_findings.append(finding)
    batches = []
    all_checks = []
    for scene, planned in COUNTS.items():
        variants = VARIANTS.get(scene) or (['lifecycle'] if scene == 'events' else ALIASES[scene][2])
        runs = planned // len(variants)
        rows = []
        for v in variants:
            for i in range(runs):
                ident = f'CP2.{scene}.{v}.{i}'
                observed = per_id.get(ident, [])
                status = 'FAIL' if any(o['status'] == 'FAIL' for o in observed) else 'PASS' if any(o['status'] == 'PASS' for o in observed) else 'BLOCKED'
                rows.append(dict(id=ident, status=status, attempts=[{k: o[k] for k in ('status', 'run_id', 'evidence')} for o in observed]))
        all_checks.extend(rows)
        counts = {s: sum(r['status'] == s for r in rows) for s in ('PASS', 'FAIL', 'BLOCKED')}
        matched = [r for r in attempts if r['batch'] == 'cp2-' + scene]
        batches.append(dict(batch='cp2-' + scene, planned=planned, counts=counts,
            executed=sum(bool(r['attempts']) for r in rows), measuredAttempts=sum(r['executed'] for r in matched),
            attemptCount=len(matched), status='FAIL' if counts['FAIL'] else 'BLOCKED' if counts['BLOCKED'] else 'PASS',
            attempts=[r['run_id'] for r in matched]))
    master = []
    for old in previous['masterRows']:
        matched = [r for r in batches if r['batch'] in old['batches']]
        status = 'FAIL' if any(r['status'] == 'FAIL' for r in matched) else 'BLOCKED' if not matched or any(r['status'] == 'BLOCKED' for r in matched) else 'PASS'
        automated_status = status
        if status == 'PASS' and ('后台暂停所有权' in old['item'] or 'audioOnly' in old['item']):
            status = 'BLOCKED'
        master.append(dict(item=old['item'], planned=old['planned'], criterion=old['criterion'], status=status, automatedStatus=automated_status,
                           executed=sum(r['executed'] for r in matched), batches=old['batches']))
    comparisons = [
        'CP0 是基线采集 COMPLETE，不设产品通过线；CP2 CHECK 有新判据，不能以矩阵全局 135 行缺证据的 BLOCKED 表判断产品回退。',
        'CP0 pod2 按指示跳过，未有等价 wait/nowait 基线；CP2 有第二条 epoch 不增长的实测疑点，不能声称相对 CP0 新增回退。',
        'CP0 raw Video bgpause=true 后台暂停 5/5、false 继续推进 5/5；CP2 plain 的 MovaPlayer 所有权与 audioOnly 三组分别核对，不混用口径。',
        'CP1 总计划 13 PASS/3 BLOCKED；其 HLS 60/60、P0-2 30/30、H35 两路各10通过属于原证据，不能外推 CP2 广告组合或 QoE。',
        'F16/Q13 复用原页，CP0 指定台账无同口径逐轮结果；本轮新增 FAIL 或 BLOCKED 是 CP2 观测，暂无同 APK/同夹具差分归因。',
        'V9/PiP 原已各5/5通过，续跑保留；liveedge 加严 hidden/paused 与 liveEdgeReach 后另跑5次。Windows 安静模式未整体验收，本轮禁止运行。',
        '原 cp2-rate-20261104-172603 中断前有两条V13a FAIL日志（0个广告rate样本），但别名驱动未生成正式CHECK；不能抹去这些历史标记，也不能当有效广告倍速度量。本次完整批次与它的采样可用性不同，不能声称产品已修复。原日志在同run-id前缀的cp2-rate.commands.log与coverage_evidence根目录同前缀.log。',
    ]
    manual = [dict(item='真实听音', status='BLOCKED', scope='广告暂停/后台静音、预热静音、audioOnly持续出声；原生 pause/mute/音轨/正音量/time-pos 是代理，媒体音量原值0，不作声学结论'),
              dict(item='PiP系统交互', status='BLOCKED', scope='HE V11只验证后台豁免；系统展开/X/mini联动和F5 keepAlive唤醒全路径仍需人工'),
              dict(item='视觉', status='BLOCKED', scope='切广告/pod/三集连播/前后台/PiP无黑帧、错画需人工视频审阅，截图不替代全程视觉验收')]
    history = dict(id='BUILD-01', status='RESOLVED', originalStatus='BLOCKED', details=previous['blockers'],
                   resolution='cc4c1a37：第二次授权构建成功；续跑没有重新构建。', stage0=stage0)
    counts = dict(masterRows=dict(Counter(r['status'] for r in master)), batches=dict(Counter(r['status'] for r in batches)),
                  plannedChecks=sum(COUNTS.values()), checks=dict(Counter(r['status'] for r in all_checks)),
                  measuredAttempts=sum(r['executed'] for r in attempts), distinctMeasuredChecks=sum(bool(r['attempts']) for r in all_checks))
    counts.update(validJudgedChecks=sum(r['status'] in ('PASS', 'FAIL') for r in all_checks),
                  missingChecks=sum(not r['attempts'] for r in all_checks),
                  observedBlockedChecks=sum(r['status']=='BLOCKED' and bool(r['attempts']) for r in all_checks))
    deviations = [
        '上一进程约17:34中断；宿主内存压力是怀疑原因，未证实。现有产物先提交00bd194d，所有原始目录保留。',
        '原 stage1 executed=40 包含5条 harness CHECK；本报告只统计正式 CP2 ID，重新计算为35条；不删除或改写原始台账。',
        '原驱动不支持按CHECK断点选择，不完整批次整批以新run-id重试，保留重复尝试；按完整ID去重，任何历史FAIL仍保留FAIL，避免重试洗白。',
        'source:null、广告记录kind覆盖、playlist回调item归属及注入内核未移交所有权已修夹具源码；原APK仍为旧夹具，修复未经设备验证时不得声称修复通过。',
        '未修改mova/lib、mova/test；没有转派、切分支、push、stash、reset；generated_plugin*、doc/notes及其他工程不进提交。',
        '本轮matrix-run产物按用户指定作为CP2证据提交；原始coverage_evidence目录保留，APK与媒体不入库。',
        '原APK CHECK的deviceStatus硬编码为“未上机”，是夹具旧标签；真机执行依据本轮run-id、设备原生读回、日志与APK哈希，不把此字段当设备检测结果。',
        'Q13期间adb服务再次重启，原logcat采集连接丢失；真实AUTORUN DONE后仅终止经路径/run-id核验的自有采集器PID40432。设备缓冲恢复15条原页VERDICT，保留主机原结果，不增加真机轮次；系统音量采样12/16不足，正式15条均BLOCKED。',
    ]
    data = dict(date='2026-11-04', generatedAt=datetime.now().astimezone().isoformat(), status='FAIL' if failures else 'BLOCKED',
                buildAttempts=2, successfulBuilds=1, resumeBuilds=0,
                apkSha256=stage0['metadata']['sha256']['signed'], apk=stage0['apk'], device=previous['device'],
                history=[history], stage0=stage0, stage1=stage1, resume=resumed, attempts=attempts, batches=batches,
                masterRows=master, checks=all_checks, counts=counts, failures=failures, restoration=restoration,
                manual=manual, comparisons=comparisons, deviations=deviations, commits=commits, legacySourceResults=legacy_findings)
    data['fixtureFixes'] = dict(deviceVerified=False, requiresNewApk=True,
        sourceCommits=['ce9a879a', 'badf5173', 'c7d81755', '669e341b'],
        pending='原APK不可应用Dart源码修复；已请求是否允许一次修复APK的明确例外，尚无答复。不把源码修复当作设备复验。',
        viewOnlyChecks=[f'CP2.bgowner.view.{i}' for i in range(5)])
    data['hostChecks'] = {phase: read(E / f'cp2-checks-resume-{phase}/results.json') for phase in ('start', 'final')}
    data['device']['mode'] = 'release; reused verified APK'
    target = ROOT / 'doc/plans/2026-11-04-cp2-results.json'
    write(target, data)
    text = '# CP2 会话、广告与后台真机结果（续跑）\n\n'
    text += f"**{data['status']}：自动证据与夹具缺陷见下；CP2 整体验收未通过。** 本人执行，未转派。设备 STG-AL00 / {SERIAL} / Android 12 arm64。\n\n"
    text += f"复用 APK SHA-256 `{data['apkSha256']}`，每批重新安装并拉回核对；正式目标190 CHECK。统计：`{counts}`。重复尝试不增加正式次数，任何历史FAIL保留。\n\n"
    text += f"去重后100个正式ID有记录：85个有PASS/FAIL判定，15个Q13记录因音量门禁BLOCKED；另90个ID缺测。因此BLOCKED共105，不表示105条都执行过。尝试数包含前置阻塞，不等于完整真机轮次。\n\n"
    text += '## 总计划 §4 CP2 逐行核对\n\n|计划行|次数|标准|正式实测|结论|\n|---|---|---|---:|---|\n'
    for r in master:
        text += f"|{r['item']}|{r['planned']}|{r['criterion']}|{r['executed']}|{r['status']}|\n"
    text += '\n后台所有权行另有PiP系统交互人工项；自动批次PASS不代表该整行人工验收完成。Windows保持BLOCKED。\n\n'
    text += '## 批次次数（按正式ID去重）\n\n|批次|尝试数|实测/计划|PASS/FAIL/BLOCKED|结论|\n|---|---:|---:|---|---|\n'
    for r in batches:
        text += f"|{r['batch']}|{r['attemptCount']}|{r['executed']}/{r['planned']}|{r['counts']}|{r['status']}|\n"
    text += '\n## 每次运行与证据\n\n|run-id|实测/计划|PASS/FAIL/BLOCKED|状态|提交|证据|\n|---|---:|---|---|---|---|\n'
    for r in attempts:
        text += f"|{r['run_id']}|{r['executed']}/{r['planned']}|{r['counts']}|{r['status']} / {r['kind']}|`{r['commit'][:8]}`|`{r['rawResult']}`|\n"
    text += '\n## FAIL 清单（原始失败全部保留）\n\n'
    for f in failures:
        text += f"- `{f['id']}` / `{f['run_id']}`：**{f['classification']}**；{f['symptom']} 证据：`{f['evidence']}`；夹具：{f['fixture'] or '无确定夹具归因'}；疑似lib：{f['libSuspect'] or '无；不据此归为产品缺陷'}。\n"
    text += '\n## 旧页原始FAIL（未冒充有效CP2 CHECK）\n\n'
    text += 'Q13原页5 PASS/10 FAIL完整恢复，但系统音量采样只有12/16，正式15 CHECK均BLOCKED。原rate中断前另有2条零广告样本FAIL。以下历史原页FAIL全部保留，不用后续PASS洗白，也不与正式CHECK次数混算。\n\n'
    for f in legacy_findings:
        if f['status'] == 'FAIL':
            text += f"- `{f['id']}` / `{f['run_id']}`：{f['classification']}；{f['detail']}；证据 `{f['evidence']}`；夹具 {f['fixture'] or '待定'}；疑似lib {f['libSuspect'] or '无'}。\n"
    text += '\n## 未完整与阻塞\n\n'
    text += '**修复夹具后的设备复验未完成。** 原APK不可应用Dart源码修改；已请求允许一次修复APK的明确例外，尚无答复，因此没有新构建。bgowner.view五条虽已修源码，仍保留原FAIL，不能宣称已重跑修复版；其余受内核所有权/事件类别/归集错误污染的批次亦需新包隔离。\n\n'
    for r in attempts:
        if r['harness'] or r['missing']:
            text += f"- `{r['run_id']}`：harness={r['harness']}；缺失/不完整字段数={len(r['missing'])}；完整列表见JSON及原始结果。\n"
    text += '\n## BUILD-01 历史（已解除）\n\n'
    text += '第一次构建 `cp2-build-20261104-164003` 因 `Could not reserve virtual memory`、snapshot加载失败、native hook exit255与compileFlutterBuildRelease失败而BLOCKED；疑似宿主提交额度/地址空间不足，未证实SDK损坏。原日志第193–222行保留于 `example/tool/coverage_evidence/matrix-cp2-build-20261104-164003/matrix-cp2-build-20261104-164003-build.driver.log`。\n\n'
    text += '之后授权的第二次构建成功（`cc4c1a37`、`cp2-build-r2-20261104-171125`），解除构建阻塞；本次续跑复用它。旧0/190报告备份保留在阶段0 sessionEvidence/previous-results.json，历史不覆盖当前产品结论。\n'
    text += '\n## 与基线差异\n\n' + ''.join('- ' + s + '\n' for s in comparisons)
    text += '\n## 人工项\n\n' + ''.join(f"- {r['item']}：{r['status']}；{r['scope']}。\n" for r in manual)
    text += '\n## 设备恢复与宿主校验\n\n'
    text += f"恢复状态 **{restoration['status']}**；原值媒体音量0、USB常亮2、reverse/forward均空。原生读回与命令见 `example/tool/coverage_evidence/cp2-resume-restored.json`。每批内存读数见续跑JSON；FreePhysicalMemory<2GiB则等待。\n\n"
    text += '续跑开工四项校验全部退出0（matrix --check、test_run_matrix 63、test_win_policy 11、test_win_job 3），证据 `example/tool/coverage_evidence/cp2-checks-resume-start/results.json`；收尾校验见 `cp2-checks-resume-final/results.json`。没有启动Windows被测应用。\n'
    text += '\n修复的6个Dart文件定向分析退出0、No issues found；证据 `example/tool/coverage_evidence/cp2-resume-dart-analyze.log`。首次分析检出playlist广告列表可空的编译错误，已补空值处理并复查通过。\n'
    text += '\n## 偏差\n\n' + ''.join('- ' + s + '\n' for s in deviations)
    target.with_suffix('.md').write_text(text, encoding='utf-8')
    print(json.dumps(dict(counts=counts, restoration=restoration['status']), ensure_ascii=False))


if __name__ == '__main__':
    main()
