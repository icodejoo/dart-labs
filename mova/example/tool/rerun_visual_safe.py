"""Reuse visual probes with semantic speed/next/skip taps and foreground guards."""
from pathlib import Path
import sys
import coverage_record
from coverage_device import adb,unlocked,request
H=Path(__file__).resolve().parent
coverage_record.RESULT=H.parents[1]/'doc/plans/2026-10-27-device-coverage-rerun.md'

def require_own_foreground():
    """Reject input outside the full foreground test activity.

    拒绝向非前台、锁屏或小尺寸测试窗口注入坐标。
    """
    unlocked()
    activity=adb('shell','dumpsys','activity','activities')
    resumed=[line for line in activity.splitlines() if 'mResumedActivity:' in line]
    if not any('com.icodejoo.mova.mova_example.coverage/' in line for line in resumed):
        raise RuntimeError('Input rejected: test package is not the resumed activity')
    rows=request('/')['records']
    video=next((r for r in reversed(rows) if r.get('kind')=='VIDEO'),None)
    if video:
        w=video.get('window',{})
        if video['state'].get('pip') or (w and (w.get('w',0)<1000 or w.get('h',0)<2200)):
            raise RuntimeError('Input rejected: test activity is PiP or not full portrait size')

def safe_input(*args):
    """Inject only after checking the current native activity.

    注入前先核对当前原生活动。
    """
    require_own_foreground()
    return adb('shell','input',*args)

mode=sys.argv[1] if len(sys.argv)>1 else 'visual'
if mode=='visual':
    path=H/'coverage_visual_final.py'
    source=path.read_text(encoding='utf-8').replace('batch25-','rerun-safe-visual-')
    source=source.replace("call('start',style='custom',preview='true')", "call('prepare-dispose','dispose')\ncall('start',style='custom',preview='true')\ncall('portrait','orientation',value='portrait')\ncall('auto','orientation',value='auto')")
    source=source.replace("adb('shell','input','tap','600','230')", "assert click_text('1x'), 'speed control 1x not found'")
    source=source.replace("adb('shell','input','tap','915','2120')", "assert click_text('立即播放'), 'NextUp play button not found'")
    source=source.replace("p=subprocess.Popen(", "require_own_foreground()\np=subprocess.Popen(")
    source=source.replace("print('SKIP_BUTTON',click_text('跳过'),flush=True)", "skipped=click_text('跳过');print('SKIP_BUTTON',skipped,flush=True);assert skipped, 'Ad skip button not found'")
else:
    path=H/'coverage_transition_final.py'
    source=path.read_text(encoding='utf-8').replace('batch28-','rerun-safe-transition-')
    source=source.replace("call('slow-start',preview='true',slowPreview='true')", "call('prepare-dispose','dispose')\ncall('slow-start',preview='true',slowPreview='true')\ncall('portrait','orientation',value='portrait')\ncall('auto','orientation',value='auto')")
source=source.replace("adb('shell','input',","safe_input(")
exec(compile(source,str(path),'exec'),{'__name__':'__main__','__file__':str(path),
    'safe_input':safe_input,'require_own_foreground':require_own_foreground})
