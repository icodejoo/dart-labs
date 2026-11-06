"""Close the failed-build CP2 checkpoint without inventing playback results."""
import json
from pathlib import Path
import re
import subprocess
from cp0_device_guard import wait_online

ROOT = Path(__file__).resolve().parents[2]
E = ROOT/'example/tool/coverage_evidence'
SERIAL = '7NQBB23606003715'
stage0 = json.loads((E/'cp2-stage0.json').read_text(encoding='utf-8'))
stage1 = json.loads((E/'cp2-stage1.json').read_text(encoding='utf-8'))
if stage0['status'] != 'BLOCKED' or stage0.get('apk') or stage1['executedChecks']:
    raise RuntimeError('This report is restricted to the failed single build')
original = json.loads((Path(stage0['evidence'])/(stage0['run_id'].join(['matrix-','-restore.json']))).read_text(encoding='utf-8'))
commands = []
def adb(*args):
    wait_online(SERIAL)
    argv = ['adb','-s',SERIAL,*map(str,args)]
    p = subprocess.run(argv,capture_output=True,timeout=60,creationflags=subprocess.CREATE_NO_WINDOW)
    text = p.stdout.decode('utf-8',errors='replace')
    commands.append(dict(argv=argv,exit=p.returncode,stdout=text,stderr=p.stderr.decode('utf-8',errors='replace')))
    if p.returncode:
        raise RuntimeError(commands[-1])
    return text
def snapshot():
    raw = adb('shell','cmd','media_session','volume','--stream','3','--get')
    match = re.search(r'volume is (\d+)',raw,re.I)
    if not match:
        raise RuntimeError('unparseable original media volume')
    mappings = dict(reverse={},forward={})
    for direction in mappings:
        for line in adb(direction,'--list').splitlines():
            parts = line.split()
            if len(parts)==3 and (direction=='reverse' or parts[0]==SERIAL):
                mappings[direction][parts[1]] = parts[2]
    return dict(volume=match[1],power=adb('shell','settings','get','global','stay_on_while_plugged_in').strip(),mappings=mappings)

restoration = dict(status='FAIL',original=original)
try:
    before = snapshot()
    restoration['before'] = before
    if before['volume'] != original['volume']:
        adb('shell','cmd','media_session','volume','--stream','3','--set',original['volume'])
    if before['power'] != original['power']:
        if original['power']=='null':
            adb('shell','settings','delete','global','stay_on_while_plugged_in')
        else:
            adb('shell','settings','put','global','stay_on_while_plugged_in',original['power'])
    # No batch installed or created mappings. A mismatch must be recorded, not
    # resolved by deleting mappings that might belong to another session.
    restoration['after'] = snapshot()
    restoration['status'] = 'VERIFIED' if restoration['after']==original else 'FAIL'
except Exception as error:
    restoration['error'] = repr(error)
restoration['commands'] = commands
(E/'cp2-session-restored.json').write_text(json.dumps(restoration,ensure_ascii=False,indent=2),encoding='utf-8')

specs = [
 ('A24/F4 广告各路径，含 HLS H15/H20/H50','各5；MP4/HLS×四路径=40','续播误差≤500ms；renderEpoch按次递增',['adpaths']),
 ('广告暂停10s','10','slot剩余时长误差≤300ms；暂停期间不发completed',['adpause']),
 ('广告后台30s，无/有守卫','各10=20','后台不发completed、不出声；回前台按守卫语义续播',['adbg']),
 ('pod第二条','原10；映射wait/nowait各10=20','每条无缝切换；第二条renderEpoch递增10/10',['pod2']),
 ('三集广告自动连播','5轮×3集','每集pre/mid；contentEnded每集一次',['playlist3']),
 ('F16倍速与Q13预热静音','两路各5=10；Q13三组各5=15','倍速恢复与CP0一致；预热静音不碰系统音量',['rate','warmmute']),
 ('后台暂停所有权/V9/PiP/H61','plain/view各5；V9/PiP/liveedge各5=25','无守卫暂停且意图假；有守卫自动续播；PiP不暂停；隐藏≥3s回边缘',['bgowner','v9','pip','liveedge']),
 ('audioOnly后台30s及视频对照','audio/videoPlain/videoGuard各10=30','audio继续出声、intent不变；视频按守卫语义暂停',['audioonly-bg']),
 ('F1事件与F7/QoE','F1=5；QoE两路各5=10','真实事件序列；内部重试与换档不产生新QoE会话',['events','qoe']),
 ('Windows广告/V10','原广告5/V10 20；本轮禁止','0崩溃；须先整体通过win-quiet-mode',[]),
]
rows = []
for name, planned, criterion, scenes in specs:
    matched = [b for b in stage1['batches'] if b['batch'] in ['cp2-'+s for s in scenes]]
    rows.append(dict(item=name,planned=planned,criterion=criterion,status='BLOCKED',executed=0,
                     batches=[b['batch'] for b in matched],
                     evidence=[b['evidence'] for b in matched] or ['doc/plans/2026-11-03-win-quiet-mode.md'],
                     reason='单次构建失败，无本轮APK' if scenes else '用户硬约束禁止Windows；安静模式未整体通过'))
build_log = 'example/tool/coverage_evidence/matrix-cp2-build-20261104-164003/matrix-cp2-build-20261104-164003-build.driver.log'
manual = [
 dict(item='真实听音',status='BLOCKED',scope='广告暂停/后台不出声、预热静音、audioOnly后台持续出声；原生pause/mute/音轨/volume仅是代理，本轮代理也未采到'),
 dict(item='PiP系统交互',status='BLOCKED',scope='系统展开/X/mini联动、F5 keepAlive唤醒全路径；V11不能替代整行，本轮V11未运行'),
 dict(item='视觉',status='BLOCKED',scope='广告切换、pod第二条、三集连播、前后台及PiP无黑帧/无错画；本轮无画面证据'),
]
comparisons = [
 'CP0为基线采集COMPLETE，不设产品通过线；APK f9df792f6dcc0b68d908906f23026dd5beeacd56d0c2d566c1b85d6c35ba1586。本轮没有APK及媒体原生读回，无法判断改善或回退。',
 'CP0 pod2按指示跳过；CP2 wait/nowait均0/10，仍没有该项新证据。CP0 raw Video bgpause true后台原生pause=yes 5/5、false继续推进5/5，不能替代CP2 MovaPlayer/MovaView所有权。',
 'CP1总计划13 PASS/3 BLOCKED，尚未整体通过；HLS 60/60、P0-2 30/30、H35恢复两路各10通过是其原证据。本轮未验证HLS广告组合及QoE单会话，不继承为CP2 PASS。',
 'CP0/CP1 Windows均未满足安静模式整体验收；本轮保持禁止Windows，未运行任何Windows被测应用。',
 '映射表复用F16/Q13既有断言；指定CP0基线文档没有同口径F16/Q13逐轮台账，本轮又无采样，不能计算这两项差异。',
]
checks = {}
for phase in ('stage0','stage1','stage2'):
    source = E/('cp2-checks-'+phase)/'results.json'
    if source.exists():
        checks[phase] = json.loads(source.read_text(encoding='utf-8'))
data = dict(date='2026-11-04',status='BLOCKED',completed='报告与恢复已完成，正式真机跑批未执行',
    startHead='7da2a56015d3e61f7b251acac0208ab1b001774d',device=dict(serial=SERIAL,model='STG-AL00',os='Android 12',abi='arm64',mode='release target; build failed'),
    apkSha256=None,apkReason='构建失败，未生成/安装CP2 release APK',buildAttempts=1,successfulBuilds=0,
    stage0=stage0,stage1=stage1,masterRows=rows,
    counts=dict(masterRows=dict(PASS=0,FAIL=0,BLOCKED=10),batches=dict(PASS=0,FAIL=0,BLOCKED=14),
                plannedChecks=190,executedChecks=0,unexecutedChecks=190,observedProductChecks=dict(PASS=0,FAIL=0,BLOCKED=0)),
    failures=[],blockers=[dict(id='BUILD-01',classification='BUILD_ENVIRONMENT',status='BLOCKED',
        symptom='Could not reserve virtual memory; dartdev/frontend_server snapshot loading failed; native asset hook exit 255; compileFlutterBuildRelease failed',
        evidence=build_log,lines='193-222',suspectedCause='宿主提交额度或虚拟地址保留不足，未证实；不是已证实SDK损坏',libSuspect=None)],
    restoration=restoration,manual=manual,comparisons=comparisons,checks=checks,
    stageCommits=dict(stage0='7a3fba21',stage1='fe2a45c4',stage2='本报告提交，见git log'),
    deviations=['唯一构建失败，安装/哈希/正式批次未完成；未重建、未替用旧APK',
        '逐批仅做前置条件检查；run-id为阻塞证据命名，不表示执行过媒体测试',
        '没有真实播放事件/原生媒体读回/时间戳URL请求；无续播、时长、静音或会话数结论',
        '首个日志重定向因目录不存在失败，未启动构建；建目录后只有一次Gradle构建',
        '阶段0初步将snapshot报错描述为加载失败；完整日志表明此前有虚拟内存保留失败，已修正归因',
        '未改lib/test，未触碰其他worktree；Windows generated_plugin等初始脏文件未提交'],
    evidencePolicy='原始证据在example/tool/coverage_evidence（gitignored），未提交APK/媒体或matrix-run文件')
target = ROOT/'doc/plans/2026-11-04-cp2-results'
Path(str(target)+'.json').write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding='utf-8')
md = '# CP2 会话、广告与后台真机检查点结果\n\n'
md += '**BLOCKED：唯一一次release构建失败；14批均缺本轮APK，正式执行0/190 CHECK。报告与恢复已收口，CP2产品验收未完成。**\n\n'
md += '本人执行，未转派。起始detached HEAD `7da2a560`；设备STG-AL00 / `7NQBB23606003715` / Android 12 arm64。APK SHA-256：**N/A**（无成功产物、无安装，未复用旧包）。唯一构建使用全量suite、release、`--max-workers=4`，无并行构建/flutter test。\n\n'
md += '阶段提交：阶段0 `7a3fba21`；阶段1 `fe2a45c4`；阶段2为本报告提交（完整hash见git log与最终汇报）。\n\n'
md += '## 总计划§4逐行核对\n\n|总计划行|计划次数|通过标准|实测|结论|批次|\n|---|---|---|---:|---|---|\n'
md += ''.join('|{item}|{planned}|{criterion}|{executed}|{status}|{batch}|\n'.format(**r,batch=', '.join(r['batches']) or '禁止执行') for r in rows)
md += '\n## 每批次数与证据\n\n以下均为前置条件BLOCKED，不是190条已执行的产品CHECK。playlist3原计划5轮×3集，本轮0集。每批解锁亮屏窗口原文与gate.json保存在对应目录。\n\n'
md += '|批次|实测/计划CHECK|结论|run-id / 证据目录|\n|---|---:|---|---|\n'
md += ''.join('|{batch}|{executed}/{planned}|{status}|`{run_id}`<br>`{evidence}`|\n'.format(**b) for b in stage1['batches'])
md += '\n## 失败与阻塞\n\n产品FAIL清单为空，原因是未进入产品执行，不能解释为产品无缺陷或0崩溃通过。唯一阻塞BUILD-01归构建环境/夹具：\n\n'
md += '- `Could not reserve virtual memory`先于dartdev/frontend_server snapshot加载错误；objective_c native asset hook退出255，compileFlutterBuildRelease失败，Gradle退出1。\n'
md += '- 疑似宿主提交额度/虚拟地址保留不足，尚未证实具体根因；失败后可用虚拟内存2,117,536 KiB、可用物理内存8,241,864 KiB。未据此声称SDK文件损坏。\n'
md += '- lib疑似位置：无可归因位置，未进入播放流程，不应凭构建环境错误指认lib。\n'
md += '- 证据：`'+build_log+'` 第193–222行；同目录build.commands.driver.log保留完整命令。阶段0原始结果`example/tool/coverage_evidence/cp2-stage0.json`。\n'
md += '\n## 与CP0/CP1对照\n\n'+''.join('- '+s+'\n' for s in comparisons)
md += '\n## 人工项\n\n'+''.join('- '+r['item']+'：'+r['status']+'；'+r['scope']+'。\n' for r in manual)
md += '\n## 校验与设备恢复\n\n开工及阶段0/1结束的四项全部通过：run_matrix --check（78批/135编号/6人工）、test_run_matrix 63、test_win_policy 11、test_win_job 3。既有ResourceWarning不改变退出0；没有启动Windows被测应用。libmpv水合检查通过。阶段2结束校验见`example/tool/coverage_evidence/cp2-checks-stage2/results.json`。\n\n'
md += '恢复状态：**'+restoration['status']+'**。原值与最终读回：媒体音量0、USB常亮2，adb reverse/forward均空；完整原生读回见`example/tool/coverage_evidence/cp2-session-restored.json`。14批均在线解锁亮屏，未触发10分钟解锁或15分钟离线等待上限；unauthorized重启adb守卫已补充，但本轮没有触发该分支。\n'
md += '\n## 偏差与边界\n\n'+''.join('- '+s+'。\n' for s in data['deviations'])
md += '\n原始证据留在本树example/tool/coverage_evidence（gitignored）。不提交APK/媒体、Windows生成文件、doc/notes、matrix-run或其他子工程；没有切分支/建分支/push/stash/reset。后续恢复验收需先解决宿主构建资源问题，获准重新构建后以新run-id执行全部正式次数；本次结论保持BLOCKED。\n'
Path(str(target)+'.md').write_text(md,encoding='utf-8')
print(json.dumps(dict(report=str(target),restoration=restoration['status'],counts=data['counts']),ensure_ascii=False),flush=True)
if restoration['status']!='VERIFIED':
    raise SystemExit(1)
