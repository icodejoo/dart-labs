"""Compact the completed CP3 campaign, retaining evidence pointers, never raw rows."""
from collections import Counter
from datetime import datetime
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
TOOL = ROOT / 'example/tool'
TARGET = ROOT / 'doc/plans/2026-11-05-cp3-results'


def feature(batch):
    if batch == 'cp1-keepalive-s7s14':
        return ('夹具端口所有权冲突', '驱动在启动前要求18080/18082/18087均空闲，但本轮共享源仍占18080，端口预检WinError10048即退出；0/10有效CHECK，未运行S7/S14五轮。',
                'example/tool/cp1_keepalive.py:99 与本轮共享源生命周期编排；无已定位lib缺陷，像素/运动复核仍需人工')
    if batch == 'gap-lifecycle':
        return ('Mini路径/夹具上下文待归因', 'gap:A15.miniPip在MovaMini.show返回后等待mini状态25s超时，尚未到PiP调用；不将此描述为已证实的系统PiP缺陷。',
                'lib/src/ui/mini/mini.dart、mini_host.dart；example/lib/main_coverage_gap.dart上下文/前态')
    if batch == 'cp0-autotier':
        return ('夹具共享入口漏注册', '驱动选择cp0-autotier，但shared suite无该分发，收到旧API idle；0个有效样本。已将无效等待收口为HARNESS/缺测，原始结果保留。',
                'example/lib/main_coverage_suite.dart；独立main_cp0_suite_verify.dart含该入口；无已定位lib缺陷')
    if batch == 'cp0-pageview':
        return ('人工前提', 'pageview功能CHECK通过；audioFocus需要来电设备或其他真实抢焦点App，保持BLOCKED。', '无已定位lib缺陷；见CP0.pageview.audioFocus原始reason')
    if batch in ('s00c-native', 's00e-native'):
        return ('夹具/驱动前提', 'API控制页未就绪，HTTP握手RemoteDisconnected；短批排序后前一HE页仍在前台。已补首条命令之前的API就绪前提，原故障保留。',
                'example/tool/coverage_device.py:46；无已定位lib缺陷（S00c采集的是Android窗口，不是Windows应用）')
    if batch.startswith('perf-'):
        return ('夹具/驱动前提', '性能控制端口18089握手失败；驱动要求预先运行main_coverage_perf.dart，冻结共享suite没有perf分发入口，未形成有效性能采样。',
                'example/tool/coverage_perf.py:1；example/lib/main_coverage_suite.dart；无已定位lib缺陷')
    if batch.startswith('he-') or batch == 'keepalive-core':
        return ('夹具共享源中断；原始FAIL保留', '共享源子进程04:21:10退出，18080/18081不可用；04:41:18恢复。HE首帧/V6/恢复全部位于中断窗口；keepalive前半失败，恢复后已有S2/S3 PASS。无有效媒体前提不能认定lib缺陷。',
                'example/tool/verify_sources/start_sources.py；原始sources.commands.driver.log；若有效源下复现再查lib/src/core/engine.dart:1359和core/kernel/mpv_kernel.dart')
    if batch in ('final-tls', 'final-tls-probe', 'final-hls', 'final-abr'):
        return ('产品契约/旧夹具口径待归因', 'A2 engine/cutover receipt的事件回执与31字段state不一致（含buffering等）；TLS另有C16.matrix/probe打开受控HTTPS失败。原始FAIL保留。',
                'lib/src/core/engine.dart (_state.emit/_emitEvent), lib/src/core/cutover/cutover_engine.dart；TLS候选core/kernel/mpv_kernel.dart；夹具verify_auto/s00d_receipt.dart:120')
    if batch == 'cp3-headers':
        return ('产品请求头路径疑似；判据混入原生 open 请求',
                'quality 列表非空且带头 probe=200，但同一正向 token 的 Range 媒体请求无 Referer=403；thumb/prefetch 正反对照通过。',
                'lib/src/core/kernel/mpv_kernel.dart:704 (_applySourceOptions), :758 (Media(uri)); lib/src/core/model/source.dart:153; loadQualities 在 engine.dart:2975')
    if batch == 'cp3-feedplayer':
        return ('产品/夹具异步时序待归因',
                '跳页后 pause 完成并等待150ms，部分轮次仍 playing=true；自动暂停与错误可见独立判断。可能与池激活后续 play 竞争。',
                'lib/src/ui/feed_player.dart:78, :306; lib/src/core/feed/engine_pool.dart:266；夹具 cp3_pages_auto.dart:240')
    if batch == 'cp3-cp1gap-bottom':
        return ('夹具', 'VOD 下直播条件组件不挂载，insertAfter liveBadge/timeshift/backToLive 无锚点；remove 的缺席不能证明挂载。仍需直播DVR夹具。',
                'example/lib/verify_auto/cp3_pages_auto.dart:363；产品候选 lib/src/ui/skins/default_skin.dart（尚无产品缺陷证据）')
    if batch == 'gap-skin':
        return ('夹具/驱动', '首轮 shared suite 缺 gap selector，启动握手超时；后续已补 selector。保留首轮，不用重发替换。',
                'example/tool/coverage_gap.py:98；无已定位 lib 缺陷')
    return ('待归因', '保留运行器/原始 CHECK 的首次结论，不能把 HARNESS 或缺判据当产品 FAIL。',
            '待根据原始 driver / logcat 定位；未改 lib')


def check_feature(ident, batch):
    if ident in ('F11.srt', 'F11.ass', 'F11.vtt'):
        return ('夹具字幕资产缺失', '18084媒体服务对test_subtitle.srt/ass/vtt均返回404；sub-text为空且无外置字幕轨道，内嵌movtext有文本。保留FAIL，不能据此认定字幕解码产品缺陷。',
                'example/lib/verify_auto/coverage_new.dart:115（HTTP未校验状态即sub-add）；原始media.driver.log 07:24:30/44/59；若有效资产仍复现再查lib/src/core/kernel/mpv_kernel.dart及原生media_kit')
    if ident in ('A2.engine.receipt', 'A2.cutover.receipt'):
        return ('产品契约/观察器口径待归因', '事件回执与31字段state快照不同；字段差异分布见failureFeatures.receiptDifferences。',
                'lib/src/core/engine.dart (_state.emit/_emitEvent)、lib/src/core/cutover/cutover_engine.dart；观察器example/lib/verify_auto/s00d_receipt.dart:120')
    if ident == 'A29.final':
        return ('旧池计数夹具口径待归因', 'activeIndex=120正确，但累计创建2个引擎，旧断言要求3；容量上限不等于必需创建数，需核对池复用语义。',
                'lib/src/core/feed/engine_pool.dart；example/lib/verify_auto/coverage_new.dart:388')
    if ident == 'N22.sttRetry':
        return ('STT启动前提/旧编号口径待归因', 'calls=0、running=false，未建立重试前提；不能证明重试产品路径失败，不升级v1人工N22整行。',
                'lib/src/core/stt/service.dart；example/lib/verify_auto/coverage_new.dart:528')
    if ident in ('C16.matrix', 'C16.probe'):
        return ('TLS产品/夹具待归因', '受控HTTPS合法证书路径也出现Failed to open、rendered=false；证书生成/CA下发与原生TLS选项需共同核对。',
                'lib/src/core/kernel/mpv_kernel.dart (_tlsSetup/按源选项)，example/tool/coverage_tls.py')
    return feature(batch)


def ledger_feature(ident):
    if ident == 'A10':
        return ('夹具重复事件口径', '输入-1和0均钳制为0.25，旧归并器要求两个0.25事件，实际同值去重只发一个，两路matched=5/6；setRate明确只在变化时发事件，原FAIL保留。', 'example/tool/matrix_evidence.py:rate_sequence；lib/src/core/engine.dart:2859、core/cutover/cutover_engine.dart:setRate')
    if ident in ('A29', 'F13'):
        return ('夹具固定池数量口径', 'feed场景active=120、创建2引擎；回收engineCount=0且accepts=[false,false]，旧规则固定要求3个false。另一路3引擎已回收；本轮dispose120为120/120 PASS，不由固定数组长度推断泄漏。', 'example/tool/matrix_rules.json:A29.poolReclaimed；example/lib/verify_auto/coverage_new.dart:388；lib/src/core/feed/engine_pool.dart')
    if ident in ('A2', 'E.MovaSizeChange', 'E.MovaQualityChange'):
        return ('产品契约/异步观察器待归因', 'A2回执快照差异；事件另有49条尺寸payload与state不一致（如0x720对0x0），2条质量事件自动对state360p。保留事件发生时原始快照，需区分产品发出顺序与观察器读回时序。', 'lib/src/core/engine.dart:1009、:3014、:3107；lib/src/core/cutover/cutover_engine.dart；example/lib/verify_auto/s00d_receipt.dart')
    if ident in ('A25', 'C15', 'F6', 'N20'):
        return ('共享源中断及fallback产品/夹具待归因', 'S2前半never rendered，位于共享源中断/恢复窗口；S6.publicFallback三次audio=absent仍phase=holding、vid=1、mute=yes。S6意图/等待与fallback原生属性仍需有效前提独立归因，不能把整个FAIL都归源中断。', 'lib/src/core/engine.dart:keepAlive/fallback；lib/src/core/kernel/mpv_kernel.dart；example/lib/main_keep_alive_verify.dart')
    if ident in ('C14', 'F8', 'N19', 'N12', 'N13'):
        return ('夹具共享源中断', 'HE V1-V7出现无首帧、signal=none、never rendered、恢复偏差1884-1922ms；均发生在04:21-04:41共享源中断窗口。正式FAIL保留，不据此确认产品缺陷。', 'example/tool/verify_sources/start_sources.py；有效源下再查lib/src/core/render/first_frame.dart、core/engine.dart、core/kernel/mpv_kernel.dart')
    if ident == 'F11':
        return check_feature('F11.srt', 'extras')
    if ident == 'C16':
        return check_feature('C16.matrix', 'final-tls')
    if ident in ('F16', 'N10'):
        return ('广告产品/夹具采样待归因', 'V13b第一轮广告rate原生样本为0，后两轮PASS；V14三轮FAIL，预热open确实抛出但failed/skipped均0，部分轮次contentReached=false。不能从零样本断定倍速错误；V14失败需独立复核。', 'example/lib/main_review_fixes_verify2.dart:_v13/_v14；lib/src/core/session/session.dart:playAdNow/_contentRate；lib/src/core/ad/ads.dart；core/cutover/cutover_engine.dart')
    return ('待归因', '见原始ledger失败子项；未放宽判据或修改lib。', '待按证据定位')


def main():
    data = json.loads(Path(str(TARGET) + '.json').read_text(encoding='utf-8'))
    manifest = json.loads((TOOL / 'matrix_manifest.json').read_text(encoding='utf-8'))
    jobs = {b['id']: b for b in manifest['batches']}
    full_ids = manifest['aliases']['cp3-full']['batches']
    full = [r for r in data['batches'] if r['stage'] == 'full']
    executed_full = {r['batch'] for r in full}
    data['fullScope'] = dict(planned=len(full_ids), executed=len(executed_full),
                             unexecuted=[k for k in full_ids if k not in executed_full],
                             cp2DedicatedExcluded=True, source='frozen cp3-full alias in cp3-pages mapping')
    data['executionComplete'] = len(executed_full) == len(full_ids)
    data['complete'] = data['executionComplete']
    if not data['complete']:
        data['stopReason'] = '六小时截止或驱动阻塞，未完成项见 fullScope.unexecuted；已运行证据全部保留。'
    data['finalizedAt'] = datetime.now().astimezone().isoformat()
    data['failureCatalog'] = []
    for row in data['batches']:
        job = jobs[row['batch']]
        argv = job['argv']
        row['plannedRuns'] = int(argv[argv.index('--runs') + 1]) if '--runs' in argv else '源内部次数，1轮'
        row['invocations'] = 1
        driver_path = Path(row['evidence'])
        if driver_path.exists():
            driver_text = driver_path.read_text(encoding='utf-8', errors='replace')
            skipped = re.findall(r'^SHOT skipped: foreground=(\S+)', driver_text, re.M)
            if skipped:
                row['skippedScreenshots'] = dict(count=len(skipped), foregrounds=dict(Counter(skipped)),
                                                reason='前台非受测应用；截图缺口不视为视觉PASS')
            host = re.findall(r'^UI_CHECK\s+(\S+)\s+(True|False)\b', driver_text, re.M)
            if host:
                row['hostUiCounts'] = dict(Counter('PASS' if value == 'True' else 'FAIL' for _, value in host))
                row['hostUiFailures'] = [ident for ident, value in host if value == 'False']
        marker = Path(row['evidence']).parent / ('matrix-' + row['runId'] + '-' + row['batch'] + '.harness-errors.jsonl')
        if marker.exists():
            incidents = [json.loads(line) for line in marker.read_text(encoding='utf-8').splitlines() if line.strip()]
            row['legacyHarness'] = dict(evidence=str(marker), count=len(incidents), commands=[
                dict(name=(r['argv'][r['argv'].index('--name') + 1] if '--name' in r.get('argv', []) else None),
                     exit=r.get('exit'), reason=r.get('error')) for r in incidents])
        row['status'] = ('FAIL' if row['kind'] == 'FAIL' or row['checkCounts'].get('FAIL') or row.get('verdictCounts', {}).get('FAIL') or row.get('subcheckFailures')
                         else 'PASS' if row['kind'] == 'OK' and not row.get('verdictCounts', {}).get('BLOCKED') else 'BLOCKED')
        # Only identifying metadata; measurements remain in original JSON files.
        from run_matrix import expand
        raw_path = Path(expand([job['result_path']], row['runId'])[0]) if job.get('result_path') else Path(row['evidence']).parent / ('matrix-' + row['runId'] + '-' + row['batch'] + '.json')
        raw = {}
        record_offset = 0
        if raw_path and raw_path.exists():
            row['rawResult'] = str(raw_path)
            raw = json.loads(raw_path.read_text(encoding='utf-8'))
            records = raw.get('records', [])
            if not job.get('native_driver'):
                start = max((i for i, r in enumerate(records) if r.get('kind') == 'BEGIN'), default=0)
                records = records[start:]
                record_offset = start
            row['blockedReasons'] = [dict(case=v.get('case'), reason=v.get('reason')) for v in raw.get('verdicts', []) if v.get('status') == 'BLOCKED']
        else:
            records = []
        if records:
            def check_status(record):
                value = record.get('status')
                if value in ('PASS', 'FAIL', 'BLOCKED'):
                    return value
                return 'PASS' if record.get('pass') is True else 'FAIL' if record.get('pass') is False else 'BLOCKED'
            row['checkCounts'] = dict(Counter(check_status(r) for r in records if r.get('kind') == 'CHECK'))
            row['status'] = ('FAIL' if row['kind'] == 'FAIL' or row['checkCounts'].get('FAIL') or row.get('verdictCounts', {}).get('FAIL') or row.get('subcheckFailures')
                             else 'PASS' if row['kind'] == 'OK' and not row.get('verdictCounts', {}).get('BLOCKED') and not row['checkCounts'].get('BLOCKED') else 'BLOCKED')
        if row.get('hostUiCounts', {}).get('FAIL'):
            row['status'] = 'FAIL'
        variants = {}
        for check in records:
            parts = str(check.get('id', '')).split('.')
            if check.get('kind') == 'CHECK' and len(parts) >= 4 and parts[0] in ('CP0', 'CP1', 'CP3'):
                variants.setdefault(parts[2], Counter())[check_status(check)] += 1
        if variants:
            row['variantCounts'] = {k: dict(v) for k, v in variants.items()}
        if row['batch'] == 'cp1-dispose120':
            summary = next((r for r in records if r.get('id') == 'CP1.dispose120.summary.0'), {})
            rounds = summary.get('numbers', {}).get('rounds', [])
            row['disposeRounds'] = dict(total=len(rounds), passed=sum(r.get('pass') is True for r in rounds),
                                        failed=sum(r.get('pass') is False for r in rounds),
                                        summaryChecks=1 if summary else 0)
        if row['batch'] == 'cp3-cp1gap-bottom':
            observations = [o for r in records if r.get('kind') == 'CHECK' for o in r.get('numbers', {}).get('after', [])]
            row['mountObservations'] = dict(total=len(observations), falsePredicates=sum(o.get('pass') is False for o in observations),
                                             missingInsertionAnchors=sorted({o.get('name') for o in observations if o.get('pass') is False}))
        existing = {f.get('id'): f for f in row.get('failures', [])}
        for verdict in raw.get('verdicts', []):
            if verdict.get('status') == 'FAIL':
                ident = verdict.get('case')
                existing.setdefault(ident, dict(id=ident))['reason'] = verdict.get('reason') or verdict.get('difference')
        for check in records:
            if check.get('kind') == 'CHECK' and check_status(check) == 'FAIL':
                existing.setdefault(check.get('id'), dict(id=check.get('id'), reason=check.get('missing') or check.get('detail')))
        row['failures'] = [dict(id=f.get('id'), reason=f.get('reason'),
                                recordIndexes=[i + record_offset for i, r in enumerate(records) if r.get('id') == f.get('id')])
                           | dict(verdictIndexes=[i for i, v in enumerate(raw.get('verdicts', [])) if v.get('case') == f.get('id')])
                           for f in existing.values()]
        subs = row.get('subcheckFailures', [])
        row['failureFeatures'] = dict(checkIds=dict(Counter(f.get('check', {}).get('id', 'LOG') for f in subs)),
                                      receiptDifferences=dict(Counter(k for f in subs for k in f.get('check', {}).get('differences', []))))
        groups = Counter((f.get('file'), f.get('check', {}).get('id'), f.get('check', {}).get('kind')) for f in subs)
        row['subcheckFailures'] = [dict(file=file, id=ident, kind=kind, count=count)
                                   for (file, ident, kind), count in groups.items()]
        by_ident = Counter(f.get('check', {}).get('id', 'LOG') for f in subs)
        for ident, count in by_ident.items():
            example = next(f for f in subs if f.get('check', {}).get('id', 'LOG') == ident)
            category, symptom, suspect = check_feature(ident, row['batch'])
            data['failureCatalog'].append(dict(stage=row['stage'], batch=row['batch'], check=ident,
                                                observations=count, category=category, symptom=symptom,
                                                suspect=suspect, evidence=example.get('file')))
        if row['status'] != 'PASS':
            category, symptom, suspect = feature(row['batch'])
            if row['stage'] == 'full' and row['batch'] == 'gap-skin':
                category = '人工视觉/PiP前提'
                symptom = '选择器修复后已实际运行；98 PASS，11 BLOCKED为截图人工复核或系统PiP按钮，未点击项不计PASS。'
                suspect = '无已定位lib缺陷；见rawResult.verdicts中的具体人工原因'
            row['triage'] = dict(category=category, symptom=symptom, suspect=suspect, libraryEdited=False)
    selected = {r['batch']: r for r in data['batches'] if r['stage'] != 'full'}
    def result(name):
        r = selected.get(name)
        return r['status'] if r else 'BLOCKED'
    precise = [selected.get('cp3-precise-' + mode) for mode in ('normal', 'paused', 'cutover')]
    repeated_precise = [r for r in full if r['batch'].startswith('cp3-precise-')]
    f3 = ('FAIL' if any(r and r['status'] == 'FAIL' for r in precise + repeated_precise)
          else 'PASS' if all(r and (r.get('precise') or {}).get('status') == 'PASS' for r in precise)
          and all((r.get('precise') or {}).get('status') == 'PASS' for r in repeated_precise) else 'BLOCKED')
    data['fullBatchCounts'] = dict(Counter(r['status'] for r in full))
    gate = data.get('comparison')
    full_stage = next(s for s in data['stages'] if s['stage'] == 'full')
    ledger_path = ROOT / full_stage['rawReport']
    raw_ledger = json.loads(ledger_path.read_text(encoding='utf-8'))
    data['ledgerFailures'] = []
    for i, row in enumerate(raw_ledger['rows']):
        if row['status'] != 'FAIL':
            continue
        category, symptom, suspect = ledger_feature(row['id'])
        failed = [dict(id=s['id'], pointer=f'rows[{i}].subitems[{j}]', sourcePointerExamples=(sources := sorted(set(re.findall(
            r'[\w.-]+\.(?:json|log|txt)(?::(?:records|line)\[\d+\])?', s['evidence']))))[:8], sourcePointerCount=len(sources))
                  for j, s in enumerate(row.get('subitems', [])) if s['status'] == 'FAIL']
        data['ledgerFailures'].append(dict(id=row['id'], status='FAIL', category=category,
            symptom=symptom, suspect=suspect, evidence=str(ledger_path), failedSubitems=failed))
    data['newBlockedExplanation'] = dict(ids=['A4', 'A22'], category='归并器全局证据完整性门禁',
        reason='本轮adResume/ads/qoe-ended/qoe-stopped/qoe-truncated/s00d-native六命令status=error；现有规则将解析/完成错误加入所有整行，A4/A22从基线PASS降BLOCKED，非已证实的这两条产品功能回归。保留正式比较，不用旧PASS覆盖。',
        evidence=str(ledger_path))
    full_status = 'FAIL' if any(r['status'] == 'FAIL' for r in full) or gate and not gate['passed'] else 'PASS' if data['complete'] and all(r['status'] == 'PASS' for r in full) else 'BLOCKED'
    data['criteria'] = [
        dict(criterion='全部自动 Android 一轮 / CP0 ledger', status=full_status,
             detail=f"{len(executed_full)}/{len(full_ids)} 批；正式135 id gate={gate}；批次故障和新页FAIL独立保留。"),
        dict(criterion='F3/A17 precise 280', status=f3, detail='normal60 / paused60 / cutover160；完整数字及cp0-result路径见F3表。'),
        dict(criterion='C05 Android 返回键/锁定', status=result('cp3-fullscreen'), detail='back5 + locked5；ACK与unlockVisible见原始CHECK。'),
        dict(criterion='C05 Windows 全屏进出20', status='BLOCKED', detail='BLOCKED-待安静模式；0/20，本次未运行Windows应用。'),
        dict(criterion='C06 主题/中英文切换10', status=result('cp3-theme'), detail='位置增量、renderEpoch、引擎identity、session identity与styleObserved联合判据。'),
        dict(criterion='C07 Referer清晰度/缩略图/预取', status=result('cp3-headers'), detail='各5 CHECK；正负各调用一次，共30次产品API。quality额外媒体请求403，原始FAIL保留；API probe本身成功。'),
        dict(criterion='C14 feed controller/autoPause/failure', status=result('cp3-feedplayer'), detail='各5；控制器pause观察失败独立于其余两组。'),
        dict(criterion='Windows 子集同CP1', status='BLOCKED', detail='BLOCKED-待安静模式；F3/dispose/HE V6需CP0同口径基线，未执行。'),
        dict(criterion='附加 C04 chrome', status=result('cp3-c04chrome'), detail='hide/drag/style/HUD各5，共20。'),
        dict(criterion='附加 CP1 bottomPatch补证', status=result('cp3-cp1gap-bottom'), detail='5 CHECK、60次挂载；VOD未具备直播锚点，夹具FAIL保留，不关闭B块。')]
    data['cp1Carryovers'] = [
        dict(row='终审7b/fallback', status='BLOCKED', result='cp1-edgepause绝对URI 20 CHECK补证；相对URI历史归因仍缺相同内核/源的复现与网络日志。'),
        dict(row='B块', status='BLOCKED', result='restore5 BLOCKED；danmaku5功能采样不替代性能基线；extract缺原生seek落点；bottomPatch夹具FAIL；skin首轮HARNESS，全量补得98 PASS/11人工BLOCKED。'),
        dict(row='Windows', status='BLOCKED', result='BLOCKED-待安静模式；未执行。')]
    pod2 = next((r for r in full if r['batch'] == 'cp0-pod2'), None)
    data['additionalCp1Evidence'] = [dict(row='CP1额外pod2.wait/nowait（不属于16条总行）',
                                         status=pod2['status'] if pod2 else 'BLOCKED', planned=20,
                                         executed=sum(pod2['checkCounts'].values()) if pod2 else 0,
                                         evidence=pod2.get('rawResult', pod2['evidence']) if pod2 else None)]
    data['historicalSupport'] = [
        dict(ids=['F3', 'A17'], source='doc/plans/2026-11-03-cp1-results.md:19',
             support='CP1 precise280已PASS，本轮专门precise280亦PASS，支持相同precise子项转PASS。',
             limit='v1 F3还含ABR、A17还含列表等范围；不能由precise单项替整行补判。'),
        dict(ids=['A23', 'F13'], source='doc/plans/2026-11-03-cp1-results.md:32',
             support='CP1 dispose120已有120/120真机PASS，支持dispose压力子项转PASS。',
             limit='v1整行的多实现与多引擎资源范围仍需逐项对账；不把旧133个BLOCKED当本轮133个新增问题。'),
        dict(source='doc/plans/2026-11-03-cp1-results.md', support='F3 precise280、H28默认90、H20/H50 60、P0-2 30、keepAlive20、dispose120等已有真机PASS。',
             limit='可支持相同子项人工复核转PASS；135 id全编号覆盖条件需逐条核对，本轮不批量继承旧PASS，不把旧BLOCKED当新增问题。'),
        dict(source='doc/plans/2026-11-04-cp2-results.md; doc/plans/2026-11-04-cp2-r4.json',
             support='CP2历史分批证据保留；不得从部分路径通过推断广告、QoE或后台整行PASS。', limit='本轮cp3-full冻结67批，不含CP2专属14批；未复制其他worktree原始证据。')]
    data['historicalSupport'].append(dict(ids=['F16', 'N10'], source='doc/plans/2026-11-04-cp2-results.md:331',
        support='CP2最终倍速/Q13自动25 PASS，V13b原生广告speed=1、返回=1.5五轮可支持对应倍速子项PASS。',
        limit='人工听音/系统交互仍BLOCKED；本轮旧review V13b零样本与V14广告失败路径不因此覆盖或改判。'))
    data['manual'] = [dict(item=s, status='BLOCKED', executed=0) for s in (
        '真实听音/锁屏音频', '视觉/快照/皮肤截图复核', 'PiP系统交互', '真实安全锁屏提示',
        'GSM与真实Wi-Fi/蜂窝路由', 'STT模型链（A31/C7）', '真实历史时移服务（C2）',
        'WHEP夹具（F15）', '守卫/调试专包（N18/N22）', 'SAF/content provider授权',
        'B07原生抽帧seek探针及直播DVR底栏夹具', '弹幕CP0同口径性能分布/批准硬线',
        'Windows：BLOCKED-待安静模式')]
    data['deviations'] += [
        'gap-skin首轮shared selector缺失为本次驱动偏差，已提交修复并保留原HARNESS。',
        '短批排序暴露S00c/S00e依赖API页前台的隐式前提；后续旧API驱动在首条命令前检查并建立控制页，不重发已发送测试。',
        '底栏VOD夹具要求直播条件锚点导致5个FAIL；未改产品或放宽原判据。',
        '部分设备CHECK带源码静态deviceStatus=未上机标签；判据依据本轮APK哈希、真实命令、原生属性和记录，不依据该静态标签。',
        '摘要只保留计数、失败id/特征和路径；matrix-run原始报告、基线ledger、280样本均留本地。']
    data['deviations'].append('早期阶段摘要误内联失败CHECK载荷，最大约971KB；后续提交已压缩为标识、统计和证据路径；按要求未改写历史，原始matrix-run报告始终未提交。')
    data['deviations'].append('缺失的共享stall.mp4再生为40s testsrc2/AAC、ultrafast/GOP25；与旧源生成器默认veryfast/GOP50/300k不同，不据此推断旧轮性能改善。专门precise使用未改动的CP0独立长GOP夹具。')
    data['deviations'].append('全量precise前主驱动已关自有共享夹具；另起的共享源监护到07:48:34才完成停止，normal第一条结果于07:48:30产生，存在约4秒重叠。保留所有原样本，不重发替换；此前独立F3专项尚未启动该监护进程。')
    data['deviations'].append('最终恢复时Huawei接受cmd media_session设音量0但读回仍6/20；确认媒体流后用6次音量降低键恢复，原生读回0/20。USB常亮2、reverse/forward空表按起始值恢复；最终摘要仅在全部读回一致后提交。')
    data['platformObservations'] = []
    for row in full:
        if row['batch'] != 'existing-pages':
            continue
        log = Path(row['evidence']).parent / ('matrix-' + row['runId'] + '-rerun-batch11-review.log')
        if log.exists():
            count = log.read_text(encoding='utf-8', errors='replace').count('SL_RESULT_MEMORY_FAILURE')
            if count:
                data['platformObservations'].append(dict(kind='OpenSLES audio resource warning', count=count,
                    evidence=str(log), interpretation='资源/夹具压力与原生音频生命周期待归因；不单凭警告改判CHECK，也不声明听感PASS。',
                    suspect='lib/src/core/kernel/mpv_kernel.dart dispose / media_kit NativePlayer生命周期'))
    # Verify the original required settings and mappings after all processes exit.
    from cp0_device_guard import wait_online
    serial = '7NQBB23606003715'
    wait_online(serial)
    def adb(*args):
        return subprocess.check_output(['adb', '-s', serial, *args], creationflags=subprocess.CREATE_NO_WINDOW).decode('utf-8', errors='replace').strip()
    first = selected.get('cp3-fullscreen')
    evidence = Path(first['evidence']).parent
    restore = json.loads((evidence / ('matrix-' + first['runId'] + '-restore.json')).read_text())
    power = adb('shell', 'settings', 'get', 'global', 'stay_on_while_plugged_in')
    volume_raw = adb('shell', 'cmd', 'media_session', 'volume', '--stream', '3', '--get')
    volume = re.search(r'volume is (\d+)', volume_raw, re.I).group(1)
    mappings = {}
    for direction in ('reverse', 'forward'):
        mappings[direction] = {p[1]: p[2] for line in adb(direction, '--list').splitlines()
                               if len(p := line.split()) == 3 and (direction == 'reverse' or p[0] == serial)}
    data['restoration'] = dict(expected=restore, observed=dict(power=power, volume=volume, mappings=mappings),
                               verified=power == restore['power'] and volume == restore['volume'] and mappings == restore['mappings'])
    if not data['restoration']['verified']:
        raise RuntimeError('Device restoration mismatch; restore explicitly before committing final report')
    data['commits'] = subprocess.check_output(['git', 'rev-list', '--reverse', '7b73146a..HEAD'], cwd=ROOT, creationflags=subprocess.CREATE_NO_WINDOW).decode().splitlines()
    Path(str(TARGET) + '.json').write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    render(data)
    print('CP3 final summary', Path(str(TARGET) + '.json').stat().st_size, 'bytes', data['fullScope'], 'restore', data['restoration']['verified'])


def render(data):
    lines = ['# CP3 真机验证结果', '', f"状态：执行完成={data['executionComplete']}；{data.get('stopReason')}。",
             f"设备：{data['device']}；起点7b73146a；本人执行，未转派；未改根lib/test。", '',
             '基线为 `2026-10-30-matrix-run-r1030.json`：135 id，2 PASS / 133 BLOCKED。原始报告及基线不提交。', '',
             '|总计划CP3标准|状态|依据|', '|---|---|---|']
    for r in data['criteria']:
        detail = r['detail'].replace('|', '/')
        lines.append(f"|{r['criterion']}|{r['status']}|{detail}|")
    lines += ['', '## APK SHA-256', '']
    for a in data['apks']:
        lines.append(f"- {a['stage']}: `{a['sha256']}`；证据 `{a['evidence']}`。")
    lines += ['', '## 各批次', '', 'PASS/FAIL/BLOCKED为证据结论；HARNESS是驱动故障，归验收BLOCKED。次数保留映射源内部口径；空CHECK列不代表没有执行。', '',
              'F3每组的1个CHECK是summary，实际60/60/160样本见下表；子场景次数与缺测见JSON variantCounts/verdictCounts。', '',
              '|阶段|批次|结论 / 运行器|源runs / 轮数|CHECK（或VERDICT）P/F/B|耗时秒|证据|', '|---|---|---|---|---|---|---|']
    for r in data['batches']:
        c = r['checkCounts'] or r.get('verdictCounts', {})
        counts = '/'.join(str(c.get(k, 0)) for k in ('PASS', 'FAIL', 'BLOCKED')) if c else ('准备步骤' if r['batch'] == 'gap-prepare' else '见源日志/缺测')
        if not r['checkCounts'] and r.get('verdictCounts'):
            counts += ' VERDICT'
        if r.get('hostUiCounts'):
            counts += '；UI ' + '/'.join(str(r['hostUiCounts'].get(k, 0)) for k in ('PASS', 'FAIL', 'BLOCKED'))
        lines.append(f"|{r['stage']}|{r['batch']}|{r['status']} / {r['kind']}|{r['plannedRuns']} / 1|{counts}|{r['seconds']}|`{r['evidence']}`|")
    for r in data['batches']:
        if r.get('skippedScreenshots'):
            lines.append(f"- {r['stage']}/{r['batch']}：跳过截图{r['skippedScreenshots']['count']}张（前台非受测应用）；人工视觉缺口保留，详情见JSON skippedScreenshots。")
    lines += ['', '## F3 与 CP0 对照', '', '|阶段/组|执行/计划|<200ms|CP0|比例差pp|失败/从头/错路/续播/非传输落点|结论|', '|---|---|---|---|---|---|---|']
    sample_paths = []
    for r in data['batches']:
        p = r.get('precise')
        if p:
            baseline = '159/160' if 'cutover' in r['batch'] else '60/60'
            counts = '/'.join(str(p.get(k)) for k in ('failures', 'fromStart', 'newWrongPath', 'newContinuedFailure', 'newNonTransportLandingFailure'))
            lines.append(f"|{r['stage']}/{r['batch']}|{p['executed']}/{p['planned']}|{p['below200']}/{p['executed']}|{baseline}|{p['deltaPercentagePoints']}|{counts}|{p['status']}|")
            sample_paths.append(f"- {r['stage']}/{r['batch']} 原始样本：`{r.get('sourceEvidence')}/cp0-result.json`。")
    lines += ['', *sample_paths]
    lines += ['', '## FAIL 与阻塞归因', '']
    for r in data['batches']:
        if r['status'] != 'PASS':
            t = r['triage']
            ids = ', '.join(str(f.get('id')) + (' records' + str(f['recordIndexes']) if f.get('recordIndexes') else ' verdicts' + str(f.get('verdictIndexes', []))) for f in r['failures'])
            lines += [f"- **{r['stage']} / {r['batch']}：{r['status']}**（{t['category']}）。{t['symptom']} 疑似位置：`{t['suspect']}`。",
                      f"  CHECK：{ids or '见缺测/harness/原始判据'}；证据 `{r.get('rawResult', r['evidence'])}`。"]
            for blocked in r.get('blockedReasons', []):
                lines.append(f"  阻塞 `{blocked['case']}`：{blocked['reason']}。")
            if r.get('legacyHarness'):
                info = r['legacyHarness']
                lines.append(f"  子命令完成问题 {info['count']}条；`{info['evidence']}`，命令名/原因见JSON legacyHarness。")
    lines += ['', '### 原始失败CHECK分类', '']
    for r in data['failureCatalog']:
        lines.append(f"- {r['stage']}/{r['batch']}/{r['check']}，观测{r['observations']}条：{r['category']}。{r['symptom']} 疑似位置 `{r['suspect']}`；证据 `{r['evidence']}`。")
    lines += ['', '## CP0 ledger 比较', '', f"`cp3_compare.py`：`{json.dumps(data.get('comparison'), ensure_ascii=False)}`。",
              f"当前ledger计数：`{data.get('ledgerCounts')}`；全量范围：`{data['fullScope']}`。"]
    lines += ['', '### 新增FAIL逐行归因', '']
    for r in data['ledgerFailures']:
        pointers=', '.join(s['pointer'] + ' ' + s['id'] for s in r['failedSubitems'])
        lines.append(f"- **{r['id']}：FAIL**（{r['category']}）。{r['symptom']} 疑似位置 `{r['suspect']}`；证据 `{r['evidence']}`：{pointers}。")
    lines.append('- 新增BLOCKED A4/A22：'+data['newBlockedExplanation']['reason'])
    for r in data['historicalSupport']:
        lines.append(f"- {r['support']} {r['limit']} 依据：`{r['source']}`。")
    lines += ['', '## CP1 三条遗留与人工项', '']
    for r in data['cp1Carryovers']:
        lines.append(f"- {r['row']}：{r['status']}；{r['result']}")
    for r in data['additionalCp1Evidence']:
        lines.append(f"- {r['row']}：{r['status']}，{r['executed']}/{r['planned']}；证据 `{r['evidence']}`。")
    for r in data['manual']:
        lines.append(f"- 人工：{r['item']}，{r['status']}，本轮自动验收不替代人工。")
    lines += ['', '## 恢复、校验与偏差', '',
              f"媒体音量、USB常亮、reverse/forward 原生读回恢复：**{data['restoration']['verified']}**。",
              f"阶段前后四项离线门禁共{len(data['checks'])}组；命令/退出码/日志路径见JSON。"]
    if data.get('sourceWatchdog'):
        lines.append(f"共享源守护：`{data['sourceWatchdog']}`；退出/恢复记录留在本地events.jsonl。")
    for r in data.get('platformObservations', []):
        lines.append(f"- {r['kind']}：{r['count']}条；{r['interpretation']} 疑似位置 `{r['suspect']}`；证据 `{r['evidence']}`。")
    lines += ['- ' + s for s in data['deviations']]
    lines += ['', '## 提交', ''] + ['- `' + s + '`' for s in data['commits']]
    Path(str(TARGET) + '.md').write_text('\n'.join(lines) + '\n', encoding='utf-8')


if __name__ == '__main__':
    main()
