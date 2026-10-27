"""Reuse existing batches with a separate result journal and prefixed evidence."""
import sys,re
from pathlib import Path
import coverage_record
H=Path(__file__).resolve().parent
coverage_record.RESULT=H.parents[1]/'doc/plans/2026-10-27-device-coverage-rerun.md'
source=(H/sys.argv[1]).read_text(encoding='utf-8')
# All historical batch artifacts become separate rerun artifacts; no verdict is copied.
source=re.sub(r'(?<!rerun-)batch(?=\d)', 'rerun-batch',source)
source=source.replace("'cleanup-volume-audioOnly.json'","'rerun-cleanup-volume-audioOnly.json'").replace("'final-volume-native-readback.txt'","'rerun-final-volume-native-readback.txt'")
source=source.replace("    print('START_CASE',name,flush=True)","    update('开始 '+name,[],['- 执行 '+group+' '+str(args)+'；以真实事件和原生读回检查对应子项。'])\n    print('START_CASE',name,flush=True)")
source=source.replace("    print('START_BATCH',name,flush=True)","    update('开始 '+name,[],['- 复用 '+group+' 页面，核验事件与设备状态；多轮计时取平均。'])\n    print('START_BATCH',name,flush=True)")
if sys.argv[1]=='coverage_widgets_ui.py':
    source=re.sub(r'def record\(name\):.*?(?=\nunlocked\(\))', "def record(name):\n    return name\n\ndef finish_record(name,item):\n    (OUT/(name+'.unavailable.txt')).write_text('Device screenrecord unavailable (previously confirmed); per-action PNG and input journals retained.',encoding='utf-8')\n\n",source,flags=re.S)
    source=source.replace("    call(tag+'-pause','pause')", "    call(tag+'-prepare-portrait','orientation',value='portrait')\n    call(tag+'-prepare-auto','orientation',value='auto')\n    call(tag+'-pause','pause')")
if sys.argv[1]=='coverage_event_audit.py':
    source=source.replace("'batch*.json'","'rerun-*.json'").replace("'event-audit.json'","'rerun-event-audit.json'")
    source=source.replace("changes.append(('E.'+name,", "ledger_name={'MovaCutoverChange':'MovaSwapChange','MovaKeepAliveChange':'MovaStandbyChange','MovaKeepAliveResume':'MovaStandbyResume'}.get(name,name)\n        changes.append(('E.'+ledger_name,")
if sys.argv[1]=='coverage_ui_final.py':
    source+="\nadb('shell','am','start','-n','com.icodejoo.mova.mova_example.coverage/com.icodejoo.mova.mova_example.MainActivity')\ncall('rerun-pip-restore-before-next-batch')\n"
if sys.argv[1]=='coverage_visual_final.py':
    source=source.replace("call('start',style='custom',preview='true')", "call('prepare-dispose','dispose')\ncall('start',style='custom',preview='true')")
if sys.argv[1]=='coverage_transition_final.py':
    source=source.replace("call('slow-start',preview='true',slowPreview='true')", "call('prepare-dispose','dispose')\ncall('slow-start',preview='true',slowPreview='true')")
exec(compile(source,str(H/sys.argv[1]),'exec'),{'__name__':'__main__','__file__':str(H/sys.argv[1])})
