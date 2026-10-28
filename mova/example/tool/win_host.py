"""Own only the Windows release probes and persist their native journals."""
from pathlib import Path
import json, subprocess, sys, time, urllib.request, urllib.parse

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
OUT = HERE / 'coverage_evidence'
DOC = ROOT / 'doc/plans/2026-10-27-device-coverage-windows-retest.md'
STATE = OUT / 'win-processes.json'

def note(text):
    """Append an immediate checkpoint to the requested report."""
    with DOC.open('a', encoding='utf-8') as f: f.write('\n- ' + text + '\n')

def request(path='/'):
    """Fetch the journal without proxying loopback traffic."""
    with urllib.request.build_opener(urllib.request.ProxyHandler({})).open('http://127.0.0.1:18093'+path, timeout=5) as r:
        return json.load(r)

def start(build):
    """Launch a visible desktop executable and a hidden source server we own."""
    note(f'开始 {build} release 进程：启动本机桌面exe；只记录和收尾自己启动的PID。')
    state = json.loads(STATE.read_text()) if STATE.exists() else {}
    if 'source' not in state:
        log = (OUT/'win-source.log').open('w')
        source = subprocess.Popen([sys.executable,'-u','-m','http.server','18094','--bind','127.0.0.1','--directory',str(HERE/'rerun-sources')], stdout=log,stderr=log,creationflags=subprocess.CREATE_NO_WINDOW)
        state['source'] = source.pid
    exe = ROOT/'example/build/windows/x64/runner/Release/mova_example.exe'
    proc = subprocess.Popen([str(exe)],cwd=exe.parent)
    state['app'] = proc.pid
    state['build'] = build
    state.setdefault('history',[]).append({'build':build,'app':proc.pid,'exe':str(exe)})
    STATE.write_text(json.dumps(state,indent=2))
    for _ in range(60):
        try:
            data=request()
            assert data['pid']==proc.pid and data['build']==build, data
            note(f'{build} 启动检查点：桌面exe PID={proc.pid}，本地源 PID={state["source"]}，HTTP读回build={build}。')
            print(json.dumps(state)); return
        except (OSError, AssertionError):time.sleep(.5)
    raise RuntimeError('release app unavailable')

def call(name, **args):
    """Save progress continuously, then checkpoint the completed command."""
    note(f'开始 {name}：参数 {args}；保存完整真实事件，超时仅防挂死。')
    data=request('/run?'+urllib.parse.urlencode(args))
    deadline=time.monotonic()+1200
    last=-1
    while True:
        (OUT/f'win-{name}.json').write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding='utf-8')
        results=[r for r in data['rows'] if r['kind']=='HLS_RESULT']
        if len(results)!=last:
            last=len(results)
            if results: print(name, len(results), 'fail',sum(not r['pass'] for r in results),flush=True)
        if data['status']!='running':break
        if time.monotonic()>deadline:raise TimeoutError(name)
        time.sleep(.3);data=request()
    errors=[r for r in data['rows'] if r['kind'] in ('SCRIPT_ERROR','UNCAUGHT')]
    note(f'{name} 检查点：status={data["status"]}，累计HLS结果={len(results)}，失败={sum(not r["pass"] for r in results)}，脚本/未捕获异常={len(errors)}；证据 example/tool/coverage_evidence/win-{name}.json。')
    if data['status']!='done' or errors:raise RuntimeError(errors)
    return data

def capture(name):
    """Capture only the owned app rectangle, with dual-screen metadata."""
    state=json.loads(STATE.read_text())
    result=subprocess.run(['powershell','-NoProfile','-File',str(HERE/'win_capture.ps1'),'-TargetPid',str(state['app']),'-OutputPath',str(OUT/f'win-{name}.png')],capture_output=True,text=True,check=True)
    (OUT/f'win-{name}-window.json').write_text(result.stdout,encoding='utf-8')

if __name__=='__main__':
    command=sys.argv[1]
    if command=='start':start(sys.argv[2])
    elif command=='basic':
        call('a23',case='dispose')
        for value in ['-1','0','NaN','100','2.5']:
            call('a12-'+value,case='zoom',value=value)
            capture('a12-'+value)
        call('a12-clear',case='clear')
    elif command=='hls':
        build=sys.argv[2]
        for mode in ['normal','cutover','paused']:
            call(f'f3-{build}-{mode}',case='hls',mode=mode,count=34)
    elif command=='stop-app':
        state=json.loads(STATE.read_text())
        note(f'开始关闭自启exe PID={state["app"]}，为下一次构建释放文件。')
        subprocess.run(['taskkill','/PID',str(state['app']),'/F'],check=True)
        note(f'exe关闭检查点：taskkill PID={state["app"]} 成功。')
