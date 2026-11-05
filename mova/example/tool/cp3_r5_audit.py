"""Audit retained fifth-round evidence, without rerunning device operations."""
import json
from pathlib import Path
import sys

import cp3_r5 as campaign


def main():
    campaign.OUT = out = Path(sys.argv[1]).resolve()
    s = json.loads((out/'state.json').read_text(encoding='utf-8'))
    data = json.loads(campaign.SUMMARY.with_suffix('.json').read_text(encoding='utf-8'))
    fourth = data['fourthRoundRevalidation']['analysis']
    for row in s['attempts']:
        folder = campaign.ROOT/row['evidence']
        raw = json.loads((folder/(folder.name+'-cp3-headers.json')).read_text(encoding='utf-8'))
        row['fixtureCompleted'] = raw.get('completed', False)
        row['sampleSetComplete'] = (not row['errors'] and
            all(row['analysis'][k]['total'] == 30 for k in ('pool-ready', 'pool-ready-cutover')) and
            row['analysis']['extract']['total'] == 60)
        row['classification'] = ('完整首批：新能力截图仍有null，未满足验收；原始失败保留' if row['sampleSetComplete'] else
                                 '重试不完整：adb unauthorized与stats连接关闭；缺少样本不计为通过')
        for path in ('pool-ready', 'pool-ready-cutover'):
            v = row['analysis'][path]
            v['over1000msCount'] = len(v['over1000ms'])
            v['timingInterpretation'] = '调用总墙钟含调度/返回开销；不由超过1000ms直接推断内部重试越界，也不放宽产品上限'
        row['analysis']['extract']['previous'] = dict(round='fourth', total=fourth['extract']['total'], success=fourth['extract']['success'], null=fourth['extract']['null'])
    first = s['attempts'][0]['analysis']
    s['comparisonWithFourthRound'] = dict(
        fourth=dict(rawNull=17, rendererFutureNull=8, after100msNull=0, total=30,
                    extract=dict(success=60, total=60)),
        fifthFirstCompleteBatch=dict(rawNull=first['pool']['originalNull'],
            rendererFutureNull=first['pool']['phases']['renderer-first-frame-gate']['null'],
            after100msNull=first['pool']['phases']['additional-wait-100']['null'], total=30,
            ordinary=dict(null=16, decoded=14, total=30), cutover=dict(null=11, decoded=19, total=30),
            extract=dict(success=60, total=60)),
        caveat='旧路径在原gate后调用；新能力从bind返回立即调用，时钟起点不同，不把数值变化当成同一调用时机的因果改善')
    readings = [int(line.split(':')[-1]) for line in (out/'build-console.log').read_text(encoding='utf-8').splitlines()
                if line.startswith('CP3 FreePhysicalMemory KiB:')]
    s['buildVerification'] = dict(dartDefines=['CP3_HEADERS_READY=true', 'CP3_HEADERS_R4=true'],
        freePhysicalMemoryKiBReadings=readings, memoryThresholdKiB=4*1024*1024,
        memoryPollSeconds=60, memoryWaitLimitMinutes=40, buildStartedFreeKiB=readings[-1],
        maxWorkers=2, virtualMemoryRetries=0,
        installationHashesMatch=all(r['installationVerification']['sha256']['signed'] ==
                                   r['installationVerification']['sha256']['device'] == s['apkSha256'] for r in s['attempts']),
        onlyHeaders=True, windowsValidation=False)
    s['deviations'] += [
        '构建守卫先等待内存约10分钟，6101884 KiB达标后才启动Gradle；无虚拟内存错误重试。',
        '唯一整批重试期间发现adb unauthorized，已先kill-server再start-server恢复在线，并重建本批reverse/forward映射；未发生持续15分钟掉线。',
        '重试在quality.1采样期间因18194/stats连接关闭提前结束，仅quality.0完整CHECK保留：普通null=6/6、解码0/6；cutover null=4/6、解码2/6；抽帧12/12。未将不完整样本并入首批30/30或另跑第三批。',
        '首批普通调用墙钟792–1085ms，cutover 854–1029ms；超1000ms样本另列，产品1秒上限不变。']
    s['conclusion'] = ('修复无效（按本次真机验收）：完整首批普通null=16/30、解码14/30，cutover null=11/30、解码19/30，'
        '均未满足null=0/30且解码30/30。两侧均暂停30/30，拒绝对照各30次均未解码且HTTP403；同批抽帧60/60。'
        '第四轮原始null17/30、等100ms后0/30；本轮旧原始null8/30、renderer后2/30、等100ms后0/30，'
        '额外等待可读不代表从bind立即调用的新能力达标。重试因传输异常不完整，不改变首批失败结论；实际原生瓶颈仍待定位')
    s['stopReason'] = '完整首批失败；已按约定整批重试一次，重试受传输异常影响未满样本；不再追加尝试。设备设置及映射已恢复。'
    import subprocess
    head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=campaign.ROOT, text=True).strip()
    if head not in s['commits']:
        s['commits'].append(head)
    campaign.PATHS.append('example/tool/cp3_r5_audit.py')
    campaign.commit(s, 'audited comparison and interrupted retry')
    print(json.dumps(dict(conclusion=s['conclusion'], restoration=s['restoration'], commits=s['commits']), ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
