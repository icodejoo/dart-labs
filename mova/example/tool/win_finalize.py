"""Audit native evidence, restore generated line endings, and clean owned PIDs."""
import hashlib,json,subprocess,time
from win_host import OUT,ROOT,STATE,DOC,note

note('开始收尾审核：从两份最终完整原生时间线重新分组计数，核对每次target/RESTART/continued；核对库文件还原哈希，再关闭自启进程并检查残留。')
summary=[]
failures=[]
for build in ['fixed','unfixed']:
    data=json.loads((OUT/f'win-f3-{build}-paused.json').read_text(encoding='utf-8'))
    assert data['status']=='done'
    assert not [r for r in data['rows'] if r['kind'] in ['SCRIPT_ERROR','UNCAUGHT']]
    for mode in ['normal','cutover','paused']:
        rows=[r for r in data['rows'] if r['kind']=='HLS_RESULT' and r['mode']==mode]
        assert len(rows)==34 and {r['iteration'] for r in rows}==set(range(34))
        assert all(r['target']>=8000 for r in rows)
        for r in rows:
            assert r['resumed']==any(abs(p-r['target'])<=500 for p in r['restarts'])
            assert r['pass']==(r['resumed'] and r['continuedOk'])
            if r['pass']:
                assert abs(r['landed']-r['target'])<=500
                if mode=='paused':assert abs(r['continued']-r['target'])<=500 and r['pause']=='yes'
                else:assert r['continued']>=r['landed']+250 and r['pause']=='no'
            if not r['pass']:
                # Include the entire mode's timeline, not just the result summary.
                # 失败保留整组时间线，包含切档前后所有事件。
                failures.append({'result':r,'timeline':[x for x in data['rows'] if x['mode']==mode]})
        summary.append({'build':build,'mode':mode,'count':len(rows),'passed':sum(r['pass'] for r in rows),
            'failed':sum(not r['pass'] for r in rows),'targetMin':min(r['target'] for r in rows),
            'targetMax':max(r['target'] for r in rows),'maxLandedError':max([abs(r['landed']-r['target']) for r in rows if r['landed']>=0],default=None),
            'restartCounts':{str(n):sum(len(r['restarts'])==n for r in rows) for n in sorted({len(r['restarts']) for r in rows})}})
(OUT/'win-f3-summary.json').write_text(json.dumps(summary,indent=2),encoding='utf-8')
(OUT/'win-f3-failures.json').write_text(json.dumps(failures,indent=2),encoding='utf-8')
hashes=json.loads((OUT/'win-engine-hashes.json').read_text())
actual=hashlib.sha256((ROOT/'lib/src/core/engine.dart').read_bytes()).hexdigest()
assert hashes['before']==hashes['restored']==actual and hashes['restoredMatches']
diff=subprocess.run(['git','diff','--','lib/src/core/engine.dart'],cwd=ROOT,capture_output=True,check=True).stdout
assert diff==(OUT/'win-f3-fix.patch').read_bytes()
(OUT/'win-f3-restored.patch').write_bytes(diff)
note('事件审计检查点：两版本各102次（每组34），target均>=8s，RESTART±500ms及原生continued判据逐条复算一致；win-f3-summary.json保存统计，win-f3-failures.json保存所有失败完整时间线。还原后的git diff也与归档win-f3-fix.patch逐字节一致。')

# Flutter rewrites generated files as LF; revert its EOL-only churn to CRLF.
# Flutter生成器写LF；仅恢复其原先CRLF，不改任何内容。
generated=[]
for name in ['generated_plugin_registrant.cc','generated_plugin_registrant.h','generated_plugins.cmake']:
    relative='example/windows/flutter/'+name
    path=ROOT/relative
    baseline=subprocess.run(['git','show','HEAD:mova/'+relative],cwd=ROOT,capture_output=True,check=True).stdout
    assert path.read_bytes().replace(b'\r\n',b'\n')==baseline
    if subprocess.run(['git','config','core.autocrlf'],cwd=ROOT,capture_output=True,text=True).stdout.strip()=='true':
        path.write_bytes(baseline.replace(b'\n',b'\r\n'))
    generated.append(relative)
note('生成文件检查点：flutter自动写入的3个Windows生成文件与HEAD内容一致，仅恢复CRLF，消除验证范围外的换行改动；未改packages/test或他人源码。')

state=json.loads(STATE.read_text())
owned=sorted({state['source'],*(item['app'] for item in state['history'])})
cleanup=[]
for process_id in owned:
    result=subprocess.run(['taskkill','/PID',str(process_id),'/F'],capture_output=True,text=True)
    cleanup.append({'pid':process_id,'exit':result.returncode,'stdout':result.stdout,'stderr':result.stderr})
time.sleep(.5)
audit=subprocess.run(['powershell','-NoProfile','-Command',
    '$ids=@('+','.join(map(str,owned))+'); Get-CimInstance Win32_Process | Where-Object { $_.ProcessId -in $ids -or ($_.Name -eq "mova_example.exe") -or ($_.Name -eq "python.exe" -and $_.CommandLine -like "*http.server*18094*") } | Select-Object ProcessId,ParentProcessId,Name,CommandLine | ConvertTo-Json -Depth 3'],capture_output=True,text=True,check=True)
(OUT/'win-cleanup.json').write_text(json.dumps({'ownedPids':owned,'actions':cleanup,'remaining':audit.stdout.strip()},ensure_ascii=False,indent=2),encoding='utf-8')
ports=subprocess.run(['powershell','-NoProfile','-Command',
    'Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Where-Object LocalPort -In 18093,18094 | Select-Object LocalPort,OwningProcess | ConvertTo-Json'],capture_output=True,text=True)
(OUT/'win-residual-ports.json').write_text(json.dumps({'stdout':ports.stdout.strip(),'stderr':ports.stderr.strip()}),encoding='utf-8')
assert not audit.stdout.strip(),audit.stdout
assert not ports.stdout.strip(),ports.stdout
note(f'清理检查点：已关闭自启exe与本地源；owned PIDs={owned}，进程残留0，18093/18094监听0；此前ADB等其他进程未关闭。证据win-cleanup.json、win-residual-ports.json。')

fixed=sum(r['failed'] for r in summary if r['build']=='fixed')
unfixed=sum(r['failed'] for r in summary if r['build']=='unfixed')
if not fixed and not unfixed:
    verdict='未能复现：Windows 上未能复现该竞态，修复无回归，F3 仍待 Android 复测。不得据此标记修复验证通过。'
elif not fixed and unfixed:
    verdict=f'PASS：未修复版复现{unfixed}次失败，修复版102次失败0，本次形成有效修复前后证据。'
else:
    verdict=f'FAIL：修复版仍失败{fixed}次，保留完整失败时间线供定位。'
lines=['\n## 最终结论\n',
    '- 基线：`flutter analyze lib test` **0 issues**，`flutter test` **1516/1516 PASS**；两条命令exit 0。\n',
    '- A23 **PASS**：普通/audioOnly、启用cutover代理/audioOnly各连续dispose两次，4/4 void completed，异常0；第二次均正常。逐调用证据：`example/tool/coverage_evidence/win-a23.json`。\n',
    '- A12 **PASS**：真实挂树画面，5/5读回符合预期（-1/0/NaN→1.0，100→100.0，2.5→2.5）；-1/0窗口截图已目视确认不塌缩。证据：`win-a12--1.png`、`win-a12-0.png`、`win-a12-NaN.json`、`win-a12-100.json`、`win-a12-2.5.json`，均位于`example/tool/coverage_evidence/`。\n',
    '- F3/A17 **'+verdict+'**\n',
    '\n### 修复前后对比\n\n| 场景 | 修复版 成功/总数 | 修复版失败 | 未修复版 成功/总数 | 未修复版失败 |\n|---|---:|---:|---:|---:|\n']
for mode in ['normal','cutover','paused']:
    a=next(r for r in summary if r['build']=='fixed' and r['mode']==mode)
    b=next(r for r in summary if r['build']=='unfixed' and r['mode']==mode)
    lines.append(f'| {mode} | {a["passed"]}/34 | {a["failed"]} | {b["passed"]}/34 | {b["failed"]} |\n')
lines.append(f'| 合计 | {102-fixed}/102 | {fixed} | {102-unfixed}/102 | {unfixed} |\n')
lines += ['\n- 原生判据：每次target取切档前mpv `time-pos`且>=8s；交替360p/180p；全部RESTART位置记录于`HLS_RESTART`/`HLS_RESULT.restarts`，任一落在target±500ms即landed；播放态continued必须原生增加至少250ms，暂停态必须保持target±500ms且原生`pause=yes`。时钟仅作为日志序号时间线与防挂死截止，不推算成功。\n',
    '- 三组分别为普通引擎播放、`MovaCutoverEngine`且`MovaCutoverConfig(enabled:true)`播放、普通引擎暂停；两版本均真实MovaPlayer挂树，Windows自动启用MovaSnapshotGuard。切档本身仍经代理转发switchQuality；没有额外调用cutoverTo。\n',
    '- 完整事件证据：`example/tool/coverage_evidence/win-f3-fixed-paused.json`与`win-f3-unfixed-paused.json`（均累计含该版本三组全部事件）；各模式独立检查点文件为`win-f3-{fixed,unfixed}-{normal,cutover,paused}.json`。统计`win-f3-summary.json`，失败及完整时间线`win-f3-failures.json`。\n',
    '- 源为Android同一套40s HLS VOD，high/low分片复制到`example/tool/rerun-sources/hls/`，Windows直接127.0.0.1:18094访问；未用Android设备或adb发命令。源服务日志`win-source.log`。\n',
    '\n### 还原核对\n\n| 状态 | engine.dart SHA256 |\n|---|---|\n',
    f'| 临时改动前 | `{hashes["before"]}` |\n| forcePark:false对照 | `{hashes["negativeControl"]}` |\n| 已还原 | `{actual}` |\n',
    '\n- **哈希完全一致**；只临时替换指定一行，使用保存的原字节恢复，保留原工作区未提交改动。补丁归档`win-f3-fix.patch`，还原后补丁`win-f3-restored.patch`逐字节一致；哈希证据`win-engine-hashes.json`，原字节备份`win-engine-fixed.bytes`。没有commit/stash/reset/checkout。\n',
    '\n### 残留进程检查\n\n',
    f'- 本次PID：修复版exe {state["history"][0]["app"]}、未修复版exe {state["history"][1]["app"]}、源 {state["source"]}；均已退出。清理后相关进程**0**，18093/18094监听**0**。详见`win-processes.json`、`win-cleanup.json`、`win-residual-ports.json`。未关闭其他窗口/进程。\n']
with DOC.open('a',encoding='utf-8') as file:file.write(''.join(lines))
print(json.dumps({'summary':summary,'verdict':verdict,'restored':actual,'remaining':audit.stdout.strip()},ensure_ascii=False,indent=2))
