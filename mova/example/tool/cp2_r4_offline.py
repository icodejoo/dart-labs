"""Rejudge only the 15 R4 failures from immutable raw JSON; no device commands."""
from collections import Counter
from copy import deepcopy
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TARGET = ROOT / 'doc/plans/2026-11-04-cp2-results'
MASTER = ROOT / 'doc/plans/2026-10-31-unified-orchestration-master-plan.md'
LABEL = 'PASS（判据修正，离线重判）'
MARKER = '\n## 第四轮离线重判\n'
NOTICE = ('夹具改了 Dart 代码，第四轮 APK 里的夹具是旧的。本节只是对已有第四轮旧证据的判据修正，'
          '不是新设备证据；未构建/安装新包，未使用真机、adb 或 Gradle。'
          '修正夹具在新 APK 上的实际记录、边沿采集及缺测处理仍需新包真机复验。')


def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def clock(rows, uri):
    frames = [r for r in rows if r.get('kind') == 'EVENT' and
              r.get('event') == 'MovaFirstFrame' and r.get('uriAtEvent') == uri]
    ends = [r for r in rows if r.get('event') == 'MovaAdEvent' and
            r.get('uri') == uri and r.get('type') == 'completed']
    assert len(frames) == len(ends) == 1, 'Missing/duplicate frame or completed'
    frame, end = frames[0], ends[0]
    start, stop = frame['us'], end['us']
    assert stop > start and isinstance(frame['state']['playing'], bool)
    playing, previous, active = frame['state']['playing'], start, 0
    edges, intervals = [], []
    for r in rows[rows.index(frame) + 1:]:
        us = r['us']
        assert us >= previous
        if us > stop:
            break
        assert not (r.get('event') == 'MovaFirstFrame' and r.get('uriAtEvent') != uri)
        if r.get('kind') != 'STATE':
            continue
        current = r['state']['playing']
        assert isinstance(current, bool)
        if current != playing:
            if playing:
                active += us - previous
                intervals.append([previous, us])
            edges.append(dict(us=us, playing=current))
            playing, previous = current, us
    if playing:
        active += stop - previous
        intervals.append([previous, stop])
    assert any(not e['playing'] for e in edges) and any(e['playing'] for e in edges)
    return dict(firstFrameUs=start, completedUs=stop, playingEdges=edges,
                activeIntervalsUs=intervals, activeUs=active,
                effectiveWallMs=active / 1000, slotErrorMs=active / 1000 - 6000)


def rejudge(failure, raw):
    ident = failure['id']
    check = next(r for r in raw['records'] if r.get('kind') == 'CHECK' and r.get('id') == ident)
    assert check['status'] == 'FAIL' and check['numbers'] == failure['numbers']
    n = check['numbers']
    # Scope by preceding CHECK as well as the iteration's unique scheduled URI.
    index = raw['records'].index(check)
    begin = max((i + 1 for i, r in enumerate(raw['records'][:index])
                 if r.get('kind') == 'CHECK'), default=0)
    rows = raw['records'][begin:index]
    if ident.startswith('CP2.pod2.'):
        f1, f2 = n['firstFrame1'], n['firstFrame2']
        first, second = n['first'], n['second']
        uris = [r['uri'] for r in rows if r.get('event') == 'MovaAdEvent' and r.get('type') == 'started']
        assert n['waitForAdReadyPre'] is False and len(uris) == 2
        valid = (n['epoch1'] >= n['epoch0'] and first['engine'] == second['engine'] and
                 first['path'] == uris[0] and second['path'] == uris[1] and
                 f1 in rows and f2 in rows and f1['uriAtEvent'] == first['path'] and
                 f2['uriAtEvent'] == second['path'] and f2['us'] > f1['us'] and
                 f1['state']['renderEpoch'] == n['epoch1'] and
                 f2['state']['renderEpoch'] == n['epoch2'])
        numbers = dict(epochs=[n['epoch0'], n['epoch1'], n['epoch2']],
                       engines=[first['engine'], second['engine']],
                       paths=[first['path'], second['path']],
                       firstFrameUs=[f1['us'], f2['us']], uriAndEpochMatched=True)
    else:
        uri = n['before']['path']
        numbers = clock(rows, uri)
        samples = n['backgroundSamples']
        positions = [s['timePosMs'] for s in samples]
        drift = positions[-1] - positions[0]
        assert drift == n['nativePauseDriftMs']
        edges = numbers['playingEdges']
        pause_windows = [(e['us'], edges[i+1]['us']) for i, e in enumerate(edges[:-1]) if not e['playing']]
        paused_completed = sum(r.get('event') == 'MovaAdEvent' and r.get('uri') == uri and
                               r.get('type') == 'completed' and
                               any(a <= r['us'] < b for a, b in pause_windows) for r in rows)
        assert paused_completed == n['pausedCompleted'] == 0
        frozen = len(samples) >= 2 and all(s['path'] == uri and s['pause'] == 'yes' and
                 s['state']['playing'] is False for s in samples) and max(positions) - min(positions) <= 300
        fg = n['foreground']
        semantics = (fg['playing'] is True and fg['intent'] is True) if '.guard.' in ident else True
        valid = (frozen and abs(drift) <= 300 and paused_completed == 0 and
                 semantics and abs(numbers['slotErrorMs']) <= 300)
        numbers.update(mediaPositionErrorMs=n['slotErrorMs'], nativePauseDriftMs=n['nativePauseDriftMs'],
                       nativePauseRangeMs=max(positions)-min(positions), pausedCompleted=n['pausedCompleted'],
                       frozen=frozen, guardSemantics=semantics)
    assert valid, f'{ident}: revised criterion failed'
    return dict(id=ident, before='FAIL', status='PASS', displayStatus=LABEL,
                run_id=failure['run_id'], evidence=failure['evidence'], numbers=numbers)


def main():
    data = read(TARGET.with_suffix('.json'))
    old = data['fourthRound']
    failures = old['failures']
    expected = ({f'CP2.pod2.nowait.ad2.{i}' for i in range(10)} |
                {f'CP2.adpause.pause.{i}' for i in (1, 4, 7, 9)} | {'CP2.adbg.guard.7'})
    assert len(failures) == 15 and {f['id'] for f in failures} == expected
    evidence, revised = {}, []
    for f in failures:
        path = ROOT / f['evidence']
        evidence[f['evidence']] = hashlib.sha256(path.read_bytes()).hexdigest()
        revised.append(rejudge(f, read(path)))
    # Keep a compact final ledger; full historical attempts already live in fourthRound.
    checks = [dict(id=c['id'], status=c['status']) for c in old['checks']]
    ids = {r['id'] for r in revised}
    for c in checks:
        if c['id'] in ids:
            c.update(status='PASS', displayStatus=LABEL, offlineRejudged=True)
    counts = {s: sum(c['status'] == s for c in checks) for s in ('PASS', 'FAIL', 'BLOCKED')}
    master = deepcopy(old['masterRows'])
    for m in master:
        cs = [c for c in checks if any(c['id'].startswith('CP2.' + b.removeprefix('cp2-') + '.') for b in m['batches'])]
        m['counts'] = {s: sum(c['status'] == s for c in cs) for s in ('PASS', 'FAIL', 'BLOCKED')}
        m['automatedStatus'] = ('FAIL' if any(c['status'] == 'FAIL' for c in cs) else
                                'BLOCKED' if not cs or any(c['status'] == 'BLOCKED' for c in cs) else 'PASS')
        changed = any(c['id'] in ids for c in cs)
        m['automatedDisplayStatus'] = LABEL if changed else m['automatedStatus']
        manual = any(s in m['item'] for s in ['后台', 'F16', 'Windows'])
        m['status'] = 'BLOCKED' if manual and m['automatedStatus'] == 'PASS' else m['automatedStatus']
        m['displayStatus'] = LABEL if changed and m['status'] == 'PASS' else m['status']
        m['reason'] = ('人工听音/系统交互未完成' if manual else '')
        if '事件' in m['item']:
            m['reason'] = '缺 CP2.qoe.manual720.4 原始 CHECK，QoE 9 PASS/1 BLOCKED，不能离线补证'
        if 'Windows' in m['item']:
            m['reason'] = '本轮禁止 Windows 被测应用；无本轮设备证据，须先通过 win-quiet-mode'
        if 'pod' in m['item']:
            m['criterion'] = 'wait 每条 epoch 递增；nowait 当前引擎直接 open，不要求 epoch 递增；两条首帧与 URI 匹配'
    result = dict(title='第四轮离线重判', date='2026-11-05', status='BLOCKED', notice=NOTICE,
                  basis='只读交接 2026-11-05-cp2-r4-offline-triage.md；原始首帧/STATE/completed 单调 us，按源和迭代绑定',
                  evidenceSha256=evidence, beforeCounts=old['counts'], counts=counts,
                  beforeNewRunCounts=old['newRunCounts'],
                  rejudgedNewRunCounts=dict(PASS=old['newRunCounts']['PASS']+15, FAIL=0, BLOCKED=0),
                  revisedChecks=revised, checks=checks, masterRows=master, manual=old['manual'],
                  hostChecks=dict(analyze='41 existing issues before/after; exact diagnostic comparison unchanged',
                                  manifest='78 batches / 135 IDs / 6 manual PASS',
                                  python='test_run_matrix + test_win_policy + test_win_job: 77 tests OK',
                                  flutter='test/cp2_criteria_test.dart: 9/9 PASS, no device'),
                  validation='doc/plans/2026-11-05-cp2-r4-offline-validation.md',
                  pendingNewApkVerification='pod2 wait/nowait and adpause/adbg corrected fixture must be rebuilt and rerun on device',
                  deviations=['按用户本次要求仅重判旧证据，未执行交接建议的新 run-id 真机复验',
                              'example 全量 analyze 存在 41 个基线 issue，修正后逐条完全一致，无新增',
                              'Windows 作业单测通过，unclosed stdout ResourceWarning 未导致失败'])
    data['fourthRoundOfflineRejudgment'] = result
    data['latestRound'], data['latestStatus'] = result['title'], result['status']
    TARGET.with_suffix('.json').write_text(json.dumps(data, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    lines = [MARKER, NOTICE, '\n依据：'+result['basis']+'。wait 判据保持每条 epoch 递增；nowait 验证同一当前引擎、两源原生 path、独立首帧归属和先后。',
             'slot 以首帧到 completed 的墙钟扣除 playing=false 完整区间；不使用 CALL/RET 或媒体位置起表。绝对误差门槛仍为 ≤300ms，保留全暂停样本冻结、漂移和守卫校验；缺首帧/边沿/completed 不判通过。',
             f"\n第四轮新执行口径：{old['newRunCounts']} → {result['rejudgedNewRunCounts']}（139 条）；合并历史正式 ID：{old['counts']} → {counts}（190 条）。15 条均 FAIL → {LABEL}；原始记录、fourthRound 及此前历史结论原样保留。",
             '\n|正式 ID|原判|离线重判|重算前 → 后数字|', '|---|---|---|---|']
    for r in revised:
        n = r['numbers']
        numbers = (f"epoch={n['epochs']}；同引擎={n['engines'][0]}；首帧 us={n['firstFrameUs']}；URI 匹配" if 'epochs' in n else
                   f"媒体误差 {n['mediaPositionErrorMs']}ms → 有效墙钟 {n['effectiveWallMs']:.3f}ms，误差 {n['slotErrorMs']:+.3f}ms；漂移 {n['nativePauseDriftMs']}ms，pausedCompleted={n['pausedCompleted']}")
        lines.append(f"|{r['id']}|FAIL|{LABEL}|{numbers}|")
    lines += ['\n原始证据 SHA-256（脚本逐次读取、核对 CHECK，详细区间/边沿见 JSON revisedChecks）：']
    lines += [''] + [f'- `{p}`：`{sha}`' for p, sha in evidence.items()]
    lines += ['\n### 总计划 CP2 最终逐行对照', '\n|总计划项|自动证据|最终结论|原因/限制|', '|---|---|---|---|']
    lines += [f"|{m['item']}|{m['automatedDisplayStatus']} {m['counts']}|{m['displayStatus']}|{m['reason']}|" for m in master]
    lines += ['\n总计划 10 行：最终 PASS 4、FAIL 0、BLOCKED 6；自动证据 PASS 8、FAIL 0、BLOCKED 2。涉及重判的自动证据使用限定标签，不能当作新包上机通过。视觉人工项另列，不以自动 PASS 替代。', '\n### 人工项与仍需新包真机复验', '\n'+NOTICE]
    lines += [''] + [f"- {m['item']}：{m['status']}；{m['scope']}。" for m in old['manual']]
    lines += ['- QoE 缺失的 CP2.qoe.manual720.4 必须补原始设备记录；离线不能补为 PASS。',
              '- 旧设备证据不能证明新 Dart 夹具运行正确，也不能证明无黑帧/无错画/实际听音及系统 PiP 交互；Windows 保留 BLOCKED。',
              '- 偏差：按本次要求以旧证据修正判据，未按交接建议执行新 run-id 真机复验；无新增设备记录、无产品 lib 修改。',
              '\n宿主校验：run_matrix --check（78 批/135 ID/6 人工）通过；三个指定 Python 单测文件共 77 tests OK；'
              '单文件无设备 Flutter test 9/9 通过；example 全量 analyze 前后均为 41 个既有 issue，逐条对比无新增。'
              '详见 [离线校验记录](2026-11-05-cp2-r4-offline-validation.md)；宿主通过不替代上述设备与人工缺口。\n']
    md = TARGET.with_suffix('.md')
    md.write_text(md.read_text(encoding='utf-8').split(MARKER)[0]+'\n'.join(lines), encoding='utf-8')
    # Update exactly the CP2 table, retaining every other checkpoint and historical record.
    text = MASTER.read_text(encoding='utf-8')
    start = text.index('### CP2 会话、广告与后台（A30 之后）')
    stop = text.index('### CP3 合并前全量', start)
    section = text[start:stop].split('\n#### 第四轮离线重判收口')[0]
    table_rows = [line for line in section.splitlines() if line.startswith('|')]
    assert len(table_rows) == 12
    new_table = ['| 项 | 次数 | 通过标准 | 自动证据 | 最终结论 |', '|---|---|---|---|---|']
    for i, line in enumerate(table_rows[2:]):
        cells = [cell.strip() for cell in line.strip('|').split('|')][:3]
        if i == 1:
            cells[2] = '首帧后按 playing 边沿扣除暂停窗口的有效墙钟误差 ≤300ms；暂停冻结/漂移及不发 completed 校验保留'
        if i == 2:
            cells[2] += '；slot 误差按首帧后有效墙钟计算，绝对值 ≤300ms'
            # Idempotent generation when rerunning the offline calculation.
            cells[2] = cells[2].split('；slot 误差')[0] + '；slot 误差按首帧后有效墙钟计算，绝对值 ≤300ms'
        if i == 3:
            cells[1] = 'wait / nowait 各 10'
            cells[2] = 'wait 每条 renderEpoch 递增；nowait 按既有契约在当前引擎直接 open，不要求 epoch 递增；两条首帧均与 URI 匹配'
        m = master[i]
        new_table.append('| ' + ' | '.join(cells + [m['automatedDisplayStatus'], m['displayStatus']]) + ' |')
    section = section.replace('\n'.join(table_rows), '\n'.join(new_table))
    details = ['\n#### 第四轮离线重判收口（2026-11-05）', '\n'+NOTICE,
               '\n最终 10 行：PASS 4 / FAIL 0 / BLOCKED 6；自动证据 8 / 0 / 2。正式 ID 合计 189 PASS（含以下 15 条限定 PASS）/ 0 FAIL / 1 BLOCKED。',
               'QoE 缺 `CP2.qoe.manual720.4` 原始 CHECK，9 PASS/1 BLOCKED；Windows 本轮禁跑，无本轮设备证据。',
               '\n|第四轮原 FAIL 正式 ID|当前结论|', '|---|---|']
    details += [f"|{r['id']}|{LABEL}|" for r in revised]
    details += ['\n人工项单列：', '', *[f"- {m['item']}：{m['status']}；{m['scope']}。" for m in old['manual']],
                '\n广告后台、Q13、后台所有权/PiP、audioOnly 的最终 BLOCKED 保留人工缺口；新 Dart 夹具需新包真机复验。'
                '原始 FAIL 和历史结论保留于结果报告；逐项数字、证据 SHA-256、最终表理由见 [CP2 结果](2026-11-04-cp2-results.md#第四轮离线重判)。\n\n']
    MASTER.write_text(text[:start]+section+'\n'.join(details)+text[stop:], encoding='utf-8')
    print(json.dumps(dict(before=old['counts'], after=counts, master=Counter(m['status'] for m in master)), ensure_ascii=False))


if __name__ == '__main__':
    main()
