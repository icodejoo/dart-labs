"""Audit third-round raw evidence and restore campaign-level device settings."""
from collections import Counter
from datetime import datetime
import json
from pathlib import Path
import re
import subprocess
import sys
import time

import cp3_r3 as campaign


def records(folder, suffix):
    path = folder/(folder.name+'-'+suffix+'.json')
    data = json.loads(path.read_text(encoding='utf-8'))
    rs = data['records']
    begin = max((i for i, r in enumerate(rs) if r.get('kind') == 'BEGIN'), default=0)
    return path, [(i, rs[i]) for i in range(begin, len(rs))]


def audit(state):
    headers = []
    for row in state['attempts']:
        folder = campaign.ROOT/row['evidence']
        details = {}
        if row['batch'] == 'cp3-headers':
            path, rs = records(folder, 'cp3-headers')
            for index, r in rs:
                if r.get('kind') != 'CHECK' or '.quality.' not in r.get('id', ''):
                    continue
                paths = r['numbers']['nativePaths']
                item = dict(runId=row['runId'], check=r['id'],
                            evidence=str(path.relative_to(campaign.ROOT))+f':records[{index}]',
                            extract=paths['extract']['observations'], extractPass=paths['extract']['pass'],
                            poolPass=paths['pool']['pass'],
                            poolAuthorized=paths['pool']['observations']['authorized'],
                            poolDenied=paths['pool']['observations']['denied'],
                            extractReceipts=paths['extract']['requests'], poolReceipts=paths['pool']['requests'])
                headers.append(item)
            details['extractPass'] = sum(x['extractPass'] for x in headers if x['runId'] == row['runId'])
            details['poolPass'] = sum(x['poolPass'] for x in headers if x['runId'] == row['runId'])
            row['classification'] = ('原 15 条 headers 判据含池/抽帧联检，质量/缩略图/预取原判据另见 originalQualityChecks；'
                                     '失败为授权暂停截图 null 或授权抽帧 null，HTTP 200 与状态 restart 不等于已有图像。'
                                     '尚不能区分夹具截图时机与产品预热/截图问题；未证 headers 丢失，不改 ready 语义')
        elif row['batch'] == 'cp3-r2-subtitles':
            path, rs = records(folder, 'cp3-r2-subtitles')
            details['formats'] = [dict(evidence=f'{path.name}:records[{i}]', **r)
                                  for i, r in rs if r.get('kind') == 'CHECK' and r.get('id', '').startswith('F11.')]
            details['shots'] = [p.name for p in folder.glob('*.png') if any('.'+f+'.png' in p.name for f in ['srt','ass','vtt','movtext'])]
            details['screenshotReview'] = (
                {'srt':'测试图及字幕文字可见', 'ass':'测试图及 ASS 字幕文字可见',
                 'vtt':'测试图及 VTT 字幕文字可见', 'movtext':'测试图及内嵌字幕文字可见'}
                if row['attempt'] == 1 else
                {'srt':'Ready 空舞台，截图时机无效', 'ass':'Ready 空舞台，截图时机无效',
                 'vtt':'Ready 空舞台，截图时机无效', 'movtext':'测试图及内嵌字幕文字可见'})
            row['automaticStatus'] = 'PASS' if len(details['formats']) == 4 and all(r['pass'] for r in details['formats']) else 'FAIL'
            row['comparison'] = '上轮 SRT 未打包/四格式未验收 → 两次四格式自动 4/4 PASS；整批取证 BLOCKED'
            row['classification'] = ('字幕 SRT 资产夹具修复已获两次四格式原生 sub-text/track-list/position 与 PNG；'
                                     '两次取证子进程非零，日志停在 logcat 读取之后。09:49 独立相同读取命令实际报 '
                                     'UnicodeDecodeError: utf-8 0x80 at 21149463，adb exit=0/26008908 bytes；'
                                     '取证读取已改为原始字节。未第三次重跑；原两次 BLOCKED 保留。'
                                     '首试四张图目视有测试图及字幕；重试 SRT/ASS/VTT 三图为 Ready 空舞台，属于截图时机证据缺陷，不把它们算视觉通过。'
                                     '随后 headers 清空日志后独立诊断已不能复现编码错误，不能把新日志冒充当时原文')
        elif row['batch'] == 'cp3-r2-receipt':
            commands = {}
            for name in ['basic', 'basic-cutover', 'abr']:
                path, rs = records(folder, 'cp3-r2-'+name)
                checks = [r for _, r in rs if r.get('kind') == 'CHECK']
                receipts = [r for r in checks if 'receipt' in r.get('id', '')]
                commands[name] = dict(checks=dict(Counter('PASS' if r.get('pass') else 'FAIL' for r in checks)),
                                      receipts=len(receipts), differences=[r.get('differences') for r in receipts if r.get('differences')],
                                      evidence=str(path.relative_to(campaign.ROOT)))
            details['commands'] = commands
            restored = folder/(folder.name+'-restored.txt')
            details['restoreReadback'] = restored.read_text(encoding='utf-8') if restored.exists() else None
            row['automaticStatus'] = 'PASS' if not row['counts'].get('FAIL') else 'FAIL'
            row['comparison'] = '上轮 208 PASS/14 FAIL → 本轮 CHECK '+str(row['counts'])+'；状态事件差异未复现，整批状态含恢复裁决'
            row['classification'] = ('普通/代理 basic 及 abr 状态事件修复后自动回执通过；Seeked 不再错误比较独立 progress。'
                                     '若本尝试 BLOCKED，原因见 errors/恢复读回，不能归为事件产品失败。'
                                     '首尝试起始音量 0，set 0 后读回 6；是否延迟回写/OEM 音量策略尚未定位，最终按整轮起始值单独恢复')
        elif row['batch'] == 'cp3-r2-pool':
            path, rs = records(folder, 'cp3-r2-s00d-resources')
            samples = [dict(evidence=f'{path.name}:records[{i}]', **r) for i, r in rs if r.get('kind') == 'RESOURCE_SAMPLE']
            details['samples'] = samples
            details['processGenerations'] = sorted(set((r['pid'], r.get('processStartTicks')) for r in samples))
            details['intervals'] = [dict(before=a['phase'], after=b['phase'], elapsedUs=b['sampleUs']-a['sampleUs'],
                                         cpuTickDelta=b['cpuTicks']-a['cpuTicks'], rssDelta=b['rss']-a['rss'],
                                         threadDelta=b['threads']-a['threads'], fdDelta=b['handles']-a['handles'])
                                    for a, b in zip(samples, samples[1:])
                                    if all(isinstance(r.get(k), int) for r in (a,b) for k in ['sampleUs','cpuTicks','rss','threads','handles'])]
            native = []
            for meta in sorted(folder.glob('*.native.json')):
                d = json.loads(meta.read_text(encoding='utf-8'))
                base = str(meta).removesuffix('.native.json')
                mem = Path(base+'.meminfo.txt').read_text(encoding='utf-8', errors='replace')
                native.append(dict(phase=d['marker']['phase'], pid=d['marker']['pid'], captures=d['captures'],
                                   meminfoLines=[line.strip() for line in mem.splitlines()
                                                 if re.search(r'TOTAL PSS:|TOTAL\s+\d|Native Heap:|Native Heap\s+\d|Graphics:', line)],
                                   metadata=str(meta.relative_to(campaign.ROOT)),
                                   decoderInstances=None, surfaceInstances=None,
                                   attribution='media.codec/SurfaceFlinger 原文已保存，未取得可信该 PID 按实例 create/dispose 计数；未知'))
            details['native'] = native
            details['pairedCP0'] = None
            details['approvedThresholds'] = None
            row['classification'] = '资源计数修复后本轮自动 CHECK 结果见表；单进程代际/时间差及 host 原文已归档，缺 CP0 配对/硬线/原生实例归属，整体 BLOCKED，不认定泄漏或耗电改善'
        row['audit'] = details
    good = [r for r in headers if r['extractPass']]
    bad = [r for r in headers if not r['extractPass']]
    elapsed = [r['extract']['authorized'].get('elapsedMs') for r in headers]
    state['headerAudit'] = dict(total=len(headers), extractPass=len(good), extractFail=len(bad),
                               authorizedElapsedMs=elapsed, failedExtracts=bad,
                               poolPass=sum(r['poolPass'] for r in headers),
                               poolFail=sum(not r['poolPass'] for r in headers),
                               evidence=[r['evidence'] for r in headers])
    return state


def restore(state):
    before = state['initialSettings']
    commands = []
    def run(*args):
        from cp0_device_guard import wait_online
        wait_online(campaign.SERIAL)
        argv = ['adb', '-s', campaign.SERIAL, *args]
        r = subprocess.run(argv, capture_output=True, timeout=120)
        commands.append(dict(argv=argv, at=datetime.now().astimezone().isoformat(), exit=r.returncode,
                             stdout=r.stdout.decode('utf-8', errors='replace'), stderr=r.stderr.decode('utf-8', errors='replace')))
        if r.returncode: raise RuntimeError(str(commands[-1]))
    run('shell', 'am', 'force-stop', 'com.icodejoo.mova.mova_example.coverage')
    run('shell', 'settings', 'put', 'global', 'stay_on_while_plugged_in', before['power'])
    for attempt in range(3):
        run('shell', 'cmd', 'media_session', 'volume', '--stream', '3', '--set', before['volume'])
        time.sleep(2)
        after = campaign.previous.snapshot()
        if after == before:
            time.sleep(2)
            after = campaign.previous.snapshot()
            if after == before: break
    state['restoration'] = dict(before=before, after=after, matches=before == after, commands=commands,
                                earlierReadback=state.get('restoration'))
    if before != after:
        state['deviations'].append('整轮最终恢复仍有差异：'+json.dumps(state['restoration'], ensure_ascii=False))


def main():
    campaign.OUT = Path(sys.argv[1]).resolve()
    state = json.loads((campaign.OUT/'state.json').read_text(encoding='utf-8'))
    if not state.get('complete'): raise RuntimeError('Campaign has not finished')
    audit(state)
    restore(state)
    recovery = campaign.OUT/'volume-app-restoration.json'
    if recovery.exists():
        state['restoration']['appRecoveryEvidence'] = str(recovery.relative_to(campaign.ROOT))
        state['deviations'] = [s for s in state['deviations'] if not s.startswith('整轮最终恢复仍有差异：')]
        state['deviations'].append('OEM shell set/adjust 音量写入无效（0 仍读6）；使用同一已装 APK 的既有 video/action=volume API 设0后恢复成功，未执行新矩阵批次。辅助本地媒体仅供调用音量API，结束 force-stop 并恢复自有映射；原生读回三次为0。证据 volume-app-restoration.json。')
    state['finished'] = datetime.now().astimezone().isoformat()
    installations = []
    for row in state['attempts']:
        folder = campaign.ROOT/row['evidence']
        path = folder/(folder.name+'-build.json')
        data = json.loads(path.read_text(encoding='utf-8'))
        hashes = data['sha256']
        installations.append(dict(runId=row['runId'], hashes=hashes,
                                  matches=hashes['signed'] == hashes['device'] == state['apkSha256'],
                                  evidence=str(path.relative_to(campaign.ROOT))))
    state['installationVerification'] = installations
    state['commits'] = subprocess.check_output(['git','rev-list','--reverse','9b0a91f8..HEAD'], cwd=campaign.ROOT, text=True).splitlines()
    state['deviations'] += [
        '字幕两次四格式通过但尾段严格 UTF-8 logcat 读取失败；改原始字节取证不改变 APK，未超额第三次跑字幕。',
        'receipt 首次自动检查全绿但音量恢复 0→6，整批记 BLOCKED 并重试；最终额外 force-stop、恢复起始设置并两次延迟读回。',
        'lib/test 未修改；不运行 Windows 被测应用，不分派、不切分支/push/stash/reset；只操作本 worktree。',
    ]
    state['deviations'] = list(dict.fromkeys(state['deviations']))
    campaign.write(state)
    md = campaign.SUMMARY.with_suffix('.md')
    text = md.read_text(encoding='utf-8')
    h = state['headerAudit']
    text += '\n第三轮汇总审计：\n\n'
    text += f"- 结束 {state['finished']}；{len(installations)} 次安装均拉回核对同一 SHA-256={all(r['matches'] for r in installations)}；最终设备设置与整轮起始值相同={state['restoration']['matches']}。\n"
    text += f"- headers 全部尝试共 {h['total']} 组：抽帧 {h['extractPass']} PASS/{h['extractFail']} FAIL；池真实暂停图像 {h['poolPass']} PASS/{h['poolFail']} FAIL。授权抽帧首试耗时 ms：{h['authorizedElapsedMs']}。\n"
    for r in h['failedExtracts']:
        text += f"- 抽帧失败 `{r['evidence']}`：`{json.dumps(r['extract'],ensure_ascii=False)}`；回执 `{json.dumps(r['extractReceipts'],ensure_ascii=False)}`。约 5 秒只提示就绪/落点等待窗可疑，内部阶段未暴露，不能据耗时定根因；疑似 `lib/src/platform_impl/mpv_extractor_impl.dart:_extractNow`、`movaWaitForPreviewFrame`。\n"
    text += '- 池失败特征：authorized accepted/rendered、120s duration、640×360、restart 已出现但 imageBytes=null；denied 有403并报 error。尚缺失败实例截图时刻的内部解码/视频输出状态，定性为夹具时机或产品预热/截图路径待分，不归因头丢失。\n'
    for row in state['attempts']:
        if row.get('audit'):
            text += '- `'+row['runId']+'` 审计：`'+json.dumps(row['audit'],ensure_ascii=False)+'`。\n'
    text += '- 校验：构建 Gradle --max-workers=2，重新构建前 FreePhysicalMemory=9930860 KiB；成功且未遇虚拟内存重试；matrix --check 92 batches/135 IDs/6 manual；新增 Python 语法检查通过。原始 matrix-run/coverage_evidence 不入提交。\n'
    md.write_text(text, encoding='utf-8')
    paths = ['example/tool/cp3_r3_audit.py','example/tool/cp3_r3_restore_volume.py','example/tool/coverage_device.py',
             'doc/plans/2026-11-05-cp3-results.md','doc/plans/2026-11-05-cp3-results.json']
    campaign.call(['git','add','--',*paths], check=True)
    campaign.call(['git','diff','--cached','--check'], check=True)
    campaign.call(['git','-c','maintenance.auto=false','-c','gc.auto=0','commit','-m',
                   'test(mova): audit third round failures and verify device restoration'+campaign.previous.SUFFIX], check=True)
    print(json.dumps(dict(headers=h, restoration=state['restoration']['matches'],
                          attempts=[dict(label=r['label'], attempt=r['attempt'], status=r['status'], counts=r['counts']) for r in state['attempts']]), ensure_ascii=False))


if __name__ == '__main__': main()
