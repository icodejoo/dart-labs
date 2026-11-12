"""Reuse existing verification pages; never infer completion from exit=0 alone."""
import json
import re
import subprocess
import sys
from pathlib import Path
TOOL=Path(__file__).resolve().parent
ALIASES={'rate':('review','v13a,v13b',['V13a','V13b']),
         'warmmute':('mute','Q13A,Q13B,Q13C',['Q13A','Q13B','Q13C']),
         'v9':('he','V9',['V9']), 'pip':('he','V11',['V11']), 'liveedge':('he','V9',['V9'])}


def reduce_alias(scene,runs,text,volume_rows=()):
    variants=ALIASES[scene][2]
    checks=[]
    volume_status, volume_detail = ('PASS', {})
    if scene=='warmmute':
        from cp2_volume import volume_proof
        volume_status, volume_detail = volume_proof(volume_rows, variants, runs)
    for variant in variants:
        if scene=='rate':
            matches=re.findall(r'RFV2\|\d+\|RESULT\|'+variant+r'\|run(\d+)\|(PASS|FAIL)\|([^\r\n]*)',text,re.I)
            rows=[(int(i)-1,status.upper(),detail) for i,status,detail in matches]
        else:
            matches=re.findall(r'VERDICT '+variant+r' (PASS|FAIL) ([^\r\n]*)',text)
            rows=[(i,status,detail) for i,(status,detail) in enumerate(matches)]
        for i in range(runs):
            found=[r for r in rows if r[0]==i]
            status=found[0][1] if len(found)==1 and len(rows)==runs else 'BLOCKED'
            detail=found[0][2] if len(found)==1 else 'missing/duplicate verdict'
            if 'n/a:' in detail or 'pipSupported=false' in detail:status='BLOCKED'
            if scene=='rate' and 'nativeSpeedComplete=false' in detail:status='BLOCKED'
            if scene=='liveedge':
                evidence=re.findall(r'V9 lifecycle=\[([^]]*)\] play=true liveEdgeReach=(true|false) positionAdvanceOver3s=(\d+)ms',text)
                if len(evidence)!=runs:status='BLOCKED'
                elif evidence[i][1]!='true' or not any(v in evidence[i][0] for v in ('hidden','paused')):status='FAIL'
            if scene=='warmmute':
                if volume_status!='PASS':status=volume_status
            checks.append(dict(kind='CHECK',id=f'CP2.{scene}.{variant}.{i}',status=status,
                numbers=dict(sourceVerdict=detail,source=ALIASES[scene][:2],systemVolume=list(volume_rows) if scene=='warmmute' else [],
                    **({'systemVolumeProof':volume_detail} if scene=='warmmute' else {}))))
    return checks


def run(args):
    from coverage_cp2 import TOOL,ROOT
    evidence=TOOL/'coverage_evidence';evidence.mkdir(exist_ok=True)
    out=evidence/('matrix-'+args.run_id);out.mkdir(exist_ok=True)
    stem='matrix-'+args.run_id+'-cp2-'+args.scene
    checks=[];harness=[];completed=False
    def command(argv):
        with (out/(stem+'.commands.log')).open('a',encoding='utf-8') as log:
            log.write(json.dumps(list(map(str,argv)))+'\n');log.flush()
            result=subprocess.run(list(map(str,argv)),cwd=ROOT,stdout=log,stderr=subprocess.STDOUT,timeout=args.timeout)
        if result.returncode:raise RuntimeError('alias command exit='+str(result.returncode))
    try:
        if args.scene=='events':
            command([sys.executable,TOOL/'coverage_suite_device.py','api','--name',stem+'-launch','--timeout','60'])
            for i in range(args.runs):
                name=stem+'-'+str(i)
                command([sys.executable,TOOL/'coverage_device.py','new','--arg','case=lifecycle','--name',name,'--timeout','180'])
                data=json.loads((evidence/(name+'.json')).read_text(encoding='utf-8'))
                records=data.get('records',[])
                begin=max((j for j,r in enumerate(records) if r.get('kind')=='BEGIN'),default=0)
                rows=[r for r in records[begin:] if r.get('kind')=='CHECK' and r.get('id')=='F1']
                status=('PASS' if rows[0].get('pass') is True else 'FAIL') if len(rows)==1 and data.get('status')=='done' else 'BLOCKED'
                checks.append(dict(kind='CHECK',id=f'CP2.events.lifecycle.{i}',status=status,numbers=dict(source=str(evidence/(name+'.json')),checks=rows,events=[r for r in records[begin:] if r.get('kind')=='LIFECYCLE'])))
            completed=True
        else:
            group,only,_=ALIASES[args.scene]
            argv=[sys.executable,TOOL/'coverage_suite_device.py',group,'--only',only,'--runs',str(args.runs),'--timeout',str(args.timeout),'--name',stem]
            if args.scene=='warmmute':argv+=['--cp2-volume']
            command(argv)
            meta=json.loads((evidence/(stem+'.run.json')).read_text(encoding='utf-8'))
            completed=meta.get('completed') is True
            text=(evidence/(stem+'.log')).read_text(encoding='utf-8',errors='replace')
            volumes=json.loads((evidence/(stem+'.volume.json')).read_text(encoding='utf-8')) if args.scene=='warmmute' else []
            checks=reduce_alias(args.scene,args.runs,text,volumes)
    except Exception as error:harness.append(repr(error))
    if args.scene=='warmmute' and not checks:
        # Retain partial verdicts and explicit volume gaps after transport or
        # final capture failure; never manufacture a missing native sample.
        log_path=evidence/(stem+'.log')
        volume_path=evidence/(stem+'.volume.json')
        text=log_path.read_text(encoding='utf-8',errors='replace') if log_path.exists() else ''
        try:
            volumes=json.loads(volume_path.read_text(encoding='utf-8')) if volume_path.exists() else []
        except (ValueError,OSError) as error:
            harness.append('volume evidence unavailable: '+repr(error));volumes=[]
        checks=reduce_alias(args.scene,args.runs,text,volumes)
    result=dict(run_id=args.run_id,group=args.scene,completed=completed,harness=harness,
        missing=[r['id'] for r in checks if r['status']=='BLOCKED'],records=checks,
        verdicts=[dict(case=r['id'],status=r['status'],numbers=r['numbers']) for r in checks])
    (out/(stem+'.json')).write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
    return 2 if harness else 1 if not completed or not checks or any(r['status']!='PASS' for r in checks) else 0
