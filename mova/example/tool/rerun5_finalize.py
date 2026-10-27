"""Generate rerun5 report using only independently audited rerun5 evidence."""
from pathlib import Path
from collections import Counter
import json,hashlib,re,socket
H=Path(__file__).resolve().parent;R=H.parents[1];O=H/'coverage_evidence';D=R/'doc/plans/2026-10-27-device-coverage-android-retest4.md'
def load(n):return json.loads((O/n).read_text(encoding='utf-8'))
def link(n,label=None):return f'[{label or n}](../../example/tool/coverage_evidence/{n})'
a=load('rerun5-hls-audit.json');s=load('rerun5-hls-summary.json');fs=load('rerun5-hls-failures.json');m=load('rerun5-build-manifest.json');state=load('rerun5-final-state.json')
v=[x for x in a if x['valid']];f=[x for x in v if not x['pass']];ex=[x for x in a if not x['valid']];retry=[x for x in v if x['retrySuccess']]
changed=[]
for n in ['rerun5-protected-tree-hashes.json','rerun5-source-hashes.json']:
 for p,h in load(n).items():
  if not (R/p).exists() or hashlib.sha256((R/p).read_bytes()).hexdigest()!=h:changed.append(p)
assert not changed,changed
assert m['signedApkSha256']==m['deviceApkSha256']
assert b'_abrHold' in (R/'lib/src/core/engine.dart').read_bytes()
assert state['engineSha256']==m['engineSha256']
assert not state['pid']['text'].strip() and state['power']['text'].strip()=='7'
music=state['audio']['text'].split('- STREAM_MUSIC:')[1].split('- STREAM_ALARM:')[0]
assert 'Max: 20' in music and 'streamVolume:6' in music and '2 (speaker): 6' in music
ports={}
for port in [18080,18084]:
 with socket.socket() as sock:ports[str(port)]=sock.connect_ex(('127.0.0.1',port))==0
assert not any(ports.values())
test=(O/'rerun5-test.log').read_text(encoding='utf-8');count=int(re.findall(r'\+(\d+): All tests passed!',test)[-1]);assert 'No issues found!' in (O/'rerun5-analyze.log').read_text(encoding='utf-8')
review={'protectedFilesChanged':changed,'sourcePortsListening':ports,'raw':len(a),'valid':len(v),'passed':len(v)-len(f),'failed':len(f),'excluded':len(ex),'failedWithAbr':sum(bool(x['abrEvents']) for x in f),'retrySuccess':len(retry),'flutterTestsPassed':count}
(O/'rerun5-final-review.json').write_text(json.dumps(review,indent=2),encoding='utf-8')
t=f'''\n\n## 基线与 F3/A17 结果

设备 `7NQBB23606003715`，隔离 Android release 包；当前 Codex 自行执行，无转派。

- `flutter analyze lib test`：0 issues、exit 0；{link('rerun5-analyze.log')}。
- `flutter test`：**{count}/{count} 全绿**、exit 0；{link('rerun5-test.log')}。
- 原始 **{len(a)}**，有效 **{len(v)}**，通过 **{len(v)-len(f)}**，失败 **{len(f)}**；剔除 **{len(ex)}**，不计成败。

| 场景 | 原始尝试 | 有效 | 通过 | 失败 | 剔除 | 其中harness-invalid |
|---|---:|---:|---:|---:|---:|---:|
'''
labels={'cutover':'cutover 代理','normal':'普通播放','paused':'暂停态'}
for base,label in list(labels.items())+[('', '合计')]:
 rows=[x for x in a if x['mode'].startswith(base)];vv=[x for x in rows if x['valid']]
 if base:assert len(vv)>=(160 if base=='cutover' else 60)
 t+=f"| {label} | {len(rows)} | {len(vv)} | {sum(x['pass'] for x in vv)} | {sum(not x['pass'] for x in vv)} | {len(rows)-len(vv)} | {sum(x['earlyResult'] or x['harnessInvalid'] for x in rows)} |\n"
t+='\n| 批次 | 状态 | 已产出结果 | SCRIPT_ERROR |\n|---|---|---:|---:|\n'
for mode,x in s.items():t+=f"| {mode} | {x['sessionStatus']} | {x['total']} | {len(x['errors'])} |\n"
t+='\n原始批次：'+'、'.join(link(f'rerun5-hls-{mode}.json') for mode in s)+'。每批仅取最后BEGIN之后，累计历史不重复计数。\n'
if any(x['errors'] for x in s.values()):t+='\n存在会话中断，全部已完成结果和SCRIPT_ERROR均保留在上述原始批次；补跑使用同一已安装包，另立批次。\n'
else:t+='\n三组均正常结束，未发生SCRIPT_ERROR或重启补跑。\n'
t+='\n逐次审计 '+link('rerun5-hls-audit.json')+'；分批汇总 '+link('rerun5-hls-summary.json')+'。\n'
t+='''
## 判据与范围

沿用rerun4验证页与40s HLS VOD、18084 high/low，交替360p/180p，真实播放器挂树；cutover enabled=true。验证页仅更新build标记，ABR配置仍为默认阈值3，未改500ms/250ms判据。

target为切档前mpv time-pos，>=8000ms才有效；原生位置>20s或<8s时仍seek回9s，等Player进度与原生差<=100ms。播放与暂停均先观测目标MovaQualityChange、duration>0和原生path等于目标URI，记录HLS_VARIANT_READY。原始RESTART全部保留，eligible标记门槛后且path为目标的读回；landed取首个target±500ms的合格RESTART。播放态原生time-pos比landed增加>=250ms且pause=no；暂停态保持target±500ms且pause=yes；最终path必须仍为目标档位。门槛、落点和续播各保留6s防挂死截止，不按墙钟推算播放位置。

未观察到目标档位完成、或结果早于完成时刻，按harness-invalid单列；target<8s沿用复位竞争剔除规则。其余失败即使夹ABR仍计失败，不为凑数放宽。

## 内核 seek 分布与重发

统计HLS_SWITCH至HLS_RESULT间KERNEL_SEEK_CALL，排除切档前复位。新QualityChange或ABR切分续播链；同链同目标调用间隔>=1.5s才算重发。靠重发成功指首次合格落点出现在重发后且最终通过；仅为事件顺序证据，没有关闭重发的反事实对照。

| 场景 | 0次 | 1次 | 2次 | 3次 | >3次 | 靠重发成功 |
|---|---:|---:|---:|---:|---:|---:|
'''
for base,label in list(labels.items())+[('', '合计')]:
 rows=[x for x in v if x['mode'].startswith(base)];q=Counter(x['seekCount'] for x in rows)
 t+=f"| {label} | {q[0]} | {q[1]} | {q[2]} | {q[3]} | {sum(n for k,n in q.items() if k>3)} | {sum(x['retrySuccess'] for x in rows)} |\n"
t+='\n仍失败seek分布：'+str(dict(sorted(Counter(x['seekCount'] for x in f).items())))+'；同一续播链首发+2次重发仍失败：'+str([(x['mode'],x['run']) for x in f if x['threeAttemptChains']])+'。总调用数不能直接等同同链尝试数。\n'
t+=f"\n靠重发成功 **{len(retry)}** 次，完整时间线索引 "+link('rerun5-hls-retry-successes.json')+'。\n'
t+='\n## 失败与剔除清单\n\n'
if fs:
 t+='| 场景/run(0起) | target | 全部RESTART | landed/continued/pause | seek数 | MovaAbrDownShift | 完整时间线 |\n|---|---:|---|---|---:|---|---|\n'
 for x in fs:
  z=x['result'];t+=f"| {x['mode']}/{x['run']} | {z['target']} | {z['restarts']} | {z['landed']}/{z['continued']}/{z['pause']} | {z['seekCount']} | {x['abrPresent']} | "+link(f"rerun5-failure-{x['mode']}-{x['run']}.json",'全部事件')+' |\n'
else:t+='本轮有效失败清单为空。\n'
t+='\n失败全集 '+link('rerun5-hls-failures.json')+'。\n\n'
if ex:
 for x in ex:t+=f"- {x['mode']}/{x['run']}，target={x['target']}ms："+'；'.join(x['exclusionReason'])+'；'+link(f"rerun5-excluded-{x['mode']}-{x['run']}.json",'完整上下文')+'。\n'
else:t+='本轮无剔除。\n'
t+='\n剔除全集 '+link('rerun5-hls-excluded.json')+'。\n'
if fs:
 first=fs[0];z=first['result']
 t+=f"\n首个有效失败：{first['mode']}/{first['run']}（从0计数），target={z['target']}ms，landed={z['landed']}，continued={z['continued']}ms，seek={z['seekCount']}次，ABR夹入={first['abrPresent']}。这是首批首个观察到的失败，不能保证固定轮次复现。复现流程为启动本轮同一release包，new case=hls、cutover=true、count=160；不修改阈值。\n"
 t+='\n首个失败关键时间线（完整EVENT/duration/progress见失败文件）：\n\n| ms | 事件 |\n|---:|---|\n'
 for row in first['timeline']:
  if row['kind'] in ['HLS_SWITCH','HLS_VARIANT_READY','HLS_RESTART','KERNEL_SEEK_CALL','KERNEL_SEEK_RETURN','HLS_RESULT'] or row['kind']=='HLS_EVENT' and row.get('type') in ['MovaQualityChange','MovaDurationChange','MovaAbrDownShift','MovaErrorEvent']:
   t+=f"| {row['ms']} | {row['kind']} "+str({k:v for k,v in row.items() if k not in ['ms','kind']})+' |\n'
 t+='\n各组最短已观察失败前缀（不是稳定复现次数）：'+str({mode:min(x['run']+1 for x in f if x['mode']==mode) for mode in s if any(x['mode']==mode for x in f)})+'。执行命令：`python example/tool/rerun5_run.py hls`。\n'
 t+='\n该残余失败按目标门槛完成后仍未命中落点计入，不能因无ABR而忽略。若原生位置持续增长，仅能说明播放器仍在走时，不能等同已正确续播。仅靠本轮外部事件无法确认为何未重发，也无法将残余失败归因于_abrHold；不在本轮修改库代码。\n'
abr=sum(bool(x['abrEvents']) for x in f)
t+=f'''\n## ABR与新问题观察

- （a）失败{'未归零' if f else '归零'}：{len(f)}/{len(v)}。
- （b）有效失败中夹MovaAbrDownShift：{abr}例，无ABR：{len(f)-abr}例。仅统计HLS_EVENT，同一事件的EVENT副本不重复计数。全部有效样本中夹ABR {sum(bool(x['abrEvents']) for x in v)}例。
- （c）本轮续播结果与原生读回见逐次审计；{'仍有失败，不能宣称续播卡住等问题已消除。' if f else '三组观测窗口内未见续播卡住，暂停态亦通过。'}与rerun4的38例全部夹ABR、最终path偏离不同，本轮需以失败清单分别判断；本轮未做可选“换档后10s内人为限速”组；现有abr用例采用GatedAbr阈值1，且现有静态源不实现throttle端点，直接调用不符合本轮同口径约束。因此没有真机证据证明真实弱网时ABR必然恢复降档，也不能把未出现ABR解释为ABR永久禁用。10s兜底与屏蔽结束reset已从当前源码只读核对，不能替代弱网实测。

## 新包核对与前几轮对比

| 轮次 | 有效 | 通过 | 失败 | 失败率 |
|---|---:|---:|---:|---:|
| rerun2 | 177 | 165 | 12 | 6.78% |
| rerun3 | 295 | 234 | 61 | 20.68% |
| rerun4 | 283 | 245 | 38 | 13.43% |
| rerun5（本轮） | {len(v)} | {len(v)-len(f)} | {len(f)} | {len(f)/len(v)*100:.2f}% |

场景数、验证页和库版本不完全相同，上表仅为描述性对比。本轮沿用rerun4验证页与判据，库修复为cb7c3ba（续播链内屏蔽ABR）。

- 隔离包 `com.icodejoo.mova.mova_example.coverage`；安装后 `{m['installedLastUpdate'][0]}`；SERVER build=`{m['buildMarker']}`，{link('rerun5-start.json')}。
- Gradle APK SHA256：`{m['gradleApkSha256']}`。
- 重签包与设备拉回APK SHA256一致：`{m['signedApkSha256']}`；{link('rerun5-build-manifest.json')}。
- engine.dart SHA256：`{m['engineSha256']}`，构建前/安装时/收尾一致，包含_abrHold。release APK不携带Dart源文件，源码身份通过编译输入哈希、含engine.dart的编译依赖、编译AOT与Gradle合并产物一致、strip后AOT与设备包一致建立证据链；{link('rerun5-build-input.json')}、{link('rerun5-build-provenance.json')}、{link('rerun5-build-dependencies.txt')}。
- 沿用coverage.init.gradle、原生库LFS SHA256核对、zipalign、既有debug证书重签和安装；{link('rerun5-build.log')}、{link('rerun5-install.log')}、{link('rerun5-certificate.txt')}。

## 收尾及范围

起测与收尾均isKeyguardShowing=false、mScreenOnFully=true、USB常亮7、媒体STREAM_MUSIC speaker=6/20。隔离包已force-stop、pid为空；仅本次启动的18080/18084源PID已结束，端口无监听。{link('rerun5-final-state.json')}、{link('rerun5-final-review.json')}。

本轮独立执行，无转派；未执行git commit/stash/reset/checkout，未修改lib/、test/、packages/，保护哈希逐项一致。保留验证页既有未提交改动，仅更新build标记；rerun4脚本与旧证据原样保留，未改../dioman或其他未提交文件。新增rerun5脚本与rerun5-证据。
'''
t+='\n结论：'+(f'仍有{len(f)}/{len(v)}有效失败，不建议F3/A17验收通过。' if f else f'本轮{len(v)}个有效样本全通过，建议F3/A17按本轮换档续播验收范围通过；真实弱网ABR恢复未覆盖，有限样本不证明竞态永不发生。')+'\n'
journal=D.read_text(encoding='utf-8').split('\n\n## 基线与 F3/A17 结果')[0];D.write_text(journal+t,encoding='utf-8')
for p in re.findall(r'\]\((\.\./\.\./[^)]+)\)',t):assert (D.parent/p).exists(),p
print(json.dumps(review,ensure_ascii=False,indent=2))
