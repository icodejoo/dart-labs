"""Offline regression tests: no adb, Flutter or device access.

纯 Python 回归单测，不连接设备、不运行 Flutter。
"""
import ast
import argparse
import contextlib
import copy
import io
import json
import os
import re
import subprocess
import sys
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import matrix_compat
import run_matrix as matrix


class MatrixTests(unittest.TestCase):
    def test_integrity_gate_does_not_poison_unrelated_rows(self):
        from matrix_evidence import reduce_evidence
        from cp3_compare import compare
        with tempfile.TemporaryDirectory(dir=matrix.TOOL) as folder:
            out = Path(folder)
            (out/'unit-good.json').write_text(json.dumps(dict(status='done', records=[dict(kind='CHECK', id='A4.ok', **{'pass': True})])))
            (out/'unit-bad.json').write_text(json.dumps(dict(status='error', records=[dict(kind='CHECK', id='A22.ok', **{'pass': True})])))
            manifest = dict(ids=['A4', 'A22'], manual=[])
            rules = {key: dict(requires=[dict(kind='check', ident=key+'.ok')]) for key in manifest['ids']}
            verdicts = reduce_evidence(manifest, out, 'unit-', rules)
            self.assertEqual(verdicts['A4']['status'], 'PASS')
            self.assertEqual(verdicts['A22']['status'], 'BLOCKED')
            self.assertEqual(len(verdicts.evidence_errors), 1)
            current = dict(rows=[dict(id='A4', status='PASS')], evidenceErrors=verdicts.evidence_errors)
            self.assertFalse(compare(dict(rows=current['rows']), current)['passed'])
            (out/'unit-malformed.json').write_text('{')
            self.assertEqual(len(reduce_evidence(manifest, out, 'unit-', rules).evidence_errors), 2)

    def test_pool_reclaimed_checks_every_created_engine_without_fixed_size(self):
        from matrix_evidence import Evidence
        rules = json.loads((matrix.TOOL/'matrix_rules.json').read_text(encoding='utf8'))
        clauses = next(r['assertions'] for r in rules['A29']['requires'] if r.get('ident') == 'A29.poolReclaimed')
        for accepts in ([False, False], [False, False, False]):
            self.assertEqual(Evidence.assertions(dict(numbers=dict(engineCount=0, accepts=accepts)), clauses), 'PASS')
        for accepts in ([], [False, True]):
            self.assertEqual(Evidence.assertions(dict(numbers=dict(engineCount=0, accepts=accepts)), clauses), 'FAIL')
        self.assertEqual(Evidence.assertions(dict(numbers=dict(engineCount=1, accepts=[False, False])), clauses), 'FAIL')

    """Test manifest, selection, verdicts and report logic / 测清单、选择、判定和汇总。"""
    def setUp(self):
        """Read only the manifest / 只读清单。"""
        self.manifest=json.loads(matrix.MANIFEST.read_text(encoding='utf-8'))

    def test_evidence_txt_is_lazy_and_volume_still_checks_native_values(self):
        from matrix_evidence import Evidence
        with tempfile.TemporaryDirectory(dir=matrix.TOOL) as folder:
            root=Path(folder)
            unused=root/'unit-unused.logcat.txt'
            unused.write_text('unrelated capture',encoding='utf-8')
            for mode in ('engine','cutover'):
                for value in (-10,0,1,30,50,100,110):
                    native=root/f'unit-rerun-native-{mode}-volume{value}.native.txt'
                    native.write_text(f'volume is {round(15*max(0,min(100,value))/100)} in range [0..15]',encoding='utf-8')
            real_read=Path.read_text
            reads=[]
            def guarded(path,*args,**kwargs):
                self.assertNotEqual(path,unused,'unrelated TXT must never be loaded')
                reads.append(path.name)
                return real_read(path,*args,**kwargs)
            with patch.object(Path,'read_text',guarded):
                evidence=Evidence(root,'unit-')
                self.assertEqual(reads,[])
                self.assertEqual(evidence.volume()[0],'PASS')
                self.assertEqual(len(reads),14)
                (root/'unit-rerun-native-engine-volume30.native.txt').write_text('volume is 15 in range [0..15]',encoding='utf-8')
                self.assertEqual(evidence.volume()[0],'FAIL')

    def test_s00e_native_host_parsers_keep_unknown_and_target_device(self):
        import coverage_s00e as host
        self.assertEqual(host.brightness('123\n'), 123)
        for raw in ('', 'null', 'Permission denied', 'auto'):
            self.assertIsNone(host.brightness(raw))
        window = '  Window #0 Window{123 '+host.PACKAGE+'/MainActivity}:\n    mAttrs={screenBrightness=0.3}\n'
        self.assertEqual(host.window_brightness(window), .3)
        self.assertIsNone(host.window_brightness(window.replace(host.PACKAGE,'another.app')))
        self.assertIsNone(host.window_brightness('permission denied'))
        audio = '''- STREAM_MUSIC:
    Current: 2 (speaker): 5, 4 (headset): 9
    Devices: speaker
- STREAM_ALARM:
    Current: 2 (speaker): 15
    Devices: speaker
'''
        self.assertEqual(host.music_volume(audio), 5)
        self.assertEqual(host.music_volume(audio.replace('Devices: speaker', 'Devices: headset')), 9)
        for raw in ('', audio.replace('Devices:', 'Unknown:'), audio.replace('speaker\n', 'bluetooth\n')):
            self.assertIsNone(host.music_volume(raw))
        status = 'Name:\tmova\nVmRSS:\t4096 kB\nThreads:\t8\n'
        stat = '42 (name (with) spaces) S ' + ' '.join(map(str, range(1, 22)))
        values = host.process_values(status, stat, '0\n1\n2\n', ' TOTAL PSS: 3000 TOTAL RSS: 4096')
        self.assertEqual(values, dict(rss=4194304, threads=8, handles=3, cpuTicks=23, pss=3072000))
        self.assertTrue(all(v is None for v in host.process_values('', '', 'Permission denied', '').values()))
        sessions = ' piid:1 uid/pid:10042/42 state:started\n piid:2 pid:43 state:paused'
        self.assertEqual(host.audio_session('pid:42 state:started\npid:43 state:paused', 42)['states'], ['started'])
        self.assertIsNone(host.audio_session(sessions, 999)['states'])
        self.assertEqual(host.audio_session(sessions, 42)['states'], ['started'])

    def test_s00e_widget_rules_recompute_every_field(self):
        from matrix_evidence import Evidence
        rules=json.loads((matrix.TOOL/'matrix_rules.json').read_text(encoding='utf-8'))
        rows=[json.loads(line) for line in (matrix.TOOL/'testdata/s00e-widgets-checks.jsonl').read_text(encoding='utf-8').splitlines()]
        for row in rows:
            clauses=next(q['assertions'] for q in rules[row['id'].split('.')[0]]['requires'] if q.get('ident')==row['id'])
            self.assertEqual(Evidence.assertions(row,clauses), 'PASS', row['id'])
            changed=copy.deepcopy(row); changed['actual']='tampered'
            self.assertEqual(Evidence.assertions(changed,clauses), 'FAIL', row['id'])
            changed=copy.deepcopy(row); del changed['actual']
            self.assertEqual(Evidence.assertions(changed,clauses), 'BLOCKED', row['id'])

    def test_s00e_inventory_never_passes_missing_checks_or_boolean_only(self):
        from matrix_evidence import Evidence
        rules=json.loads((matrix.TOOL/'matrix_rules.json').read_text(encoding='utf-8'))
        inventory=json.loads((matrix.TOOL/'s00e_rules_inventory.json').read_text(encoding='utf-8'))
        with tempfile.TemporaryDirectory(dir=matrix.TOOL) as folder:
            evidence=Evidence(folder,'absent-')
            for target,items in inventory.items():
                for item in items:
                    spec=next(q for q in rules[target]['requires'] if q.get('ident')==item['check'])
                    self.assertTrue(spec['assertions'],item['check'])
                    self.assertEqual(evidence.check(item['check'],assertions=spec['assertions'])[0],'BLOCKED')
                    self.assertEqual(Evidence.assertions(dict(numbers={},**{'pass':True}),spec['assertions']),'BLOCKED')

    def test_s00e_resource_and_texture_rules_reject_spoofed_totals(self):
        from matrix_evidence import Evidence
        self.assertEqual(Evidence.assertions(dict(numbers=dict(after=[])),
            [dict(field='numbers.after.2',op='eq',value=0)]),'BLOCKED')
        clauses=[dict(field='numbers.calls',op='count_where',other='numbers.created',where={'method':'VideoOutputManager.Create','replied':True})]
        row=dict(numbers=dict(calls=[dict(method='VideoOutputManager.Create',replied=True)],created=1))
        self.assertEqual(Evidence.assertions(row,clauses),'PASS')
        row['numbers']['created']=2
        self.assertEqual(Evidence.assertions(row,clauses),'FAIL')
        row=dict(numbers=dict(before=dict(rss=100),after=dict(rss=121)))
        clauses=[dict(field='numbers.after.rss',op='delta_le',baseline='numbers.before.rss',value=20)]
        self.assertEqual(Evidence.assertions(row,clauses),'FAIL')
        row['numbers']['before']['rss']=None
        self.assertEqual(Evidence.assertions(row,clauses),'BLOCKED')

    def test_s00e_seek_count_reparses_native_command_lines(self):
        from matrix_evidence import Evidence
        row=dict(numbers=dict(lines=[
            '[cplayer] Run command: seek, flags=64, args=[target="12.000000", flags="absolute+exact"]',
            '[cplayer] Run command: seek, flags=64, args=[target="0.000000", flags="absolute+exact"]',
            '[cplayer] Run command: seek, flags=64, args=[target="12.000000", flags="absolute+exact"]'],count=2))
        clauses=[dict(field='numbers.lines',op='mpv_seek_count',target=12,other='numbers.count')]
        self.assertEqual(Evidence.assertions(row,clauses),'PASS')
        row['numbers']['count']=3
        self.assertEqual(Evidence.assertions(row,clauses),'FAIL')
        row['numbers']['lines']=[]
        self.assertEqual(Evidence.assertions(row,clauses),'BLOCKED')
        def sample(cpu):
            return dict(before=dict(cpuTicks=10,properties={'time-pos':dict(error='success',data=1)}),
                        after=dict(cpuTicks=10+cpu,properties={'time-pos':dict(error='success',data=3)}))
        row=dict(numbers=dict(audio=sample(12),video=sample(10)))
        clauses=[dict(field='numbers.audio',other='numbers.video',op='cpu_per_media_le',scale=1.1,minimum_media_seconds=2)]
        self.assertEqual(Evidence.assertions(row,clauses),'FAIL')
        row['numbers']['audio']['after']['cpuTicks']=15
        self.assertEqual(Evidence.assertions(row,clauses),'PASS')
        row['numbers']['audio']['after']['properties']['time-pos']['data']=1.2
        self.assertEqual(Evidence.assertions(row,clauses),'BLOCKED')

    def test_s00e_ipc_parser_uses_real_reply_ids_without_device(self):
        import coverage_s00e as host
        class Stream:
            def __enter__(self):return self
            def __exit__(self,*args):pass
            def write(self,data):self.command=json.loads(data)
            def flush(self):pass
            def readline(self):
                key=self.command['command'][1]
                return (json.dumps(dict(request_id=self.command['request_id'],
                    error='property unavailable' if key=='video-dec-params' else 'success',
                    data='no' if key=='vid' else None))+'\n').encode()
        class Connection:
            def __enter__(self):return self
            def __exit__(self,*args):pass
            def settimeout(self,value):pass
            def makefile(self,*args):return Stream()
        commands=[]
        def adb(*args):
            commands.append(args);return '18084' if args[0]=='forward' and args[1]=='tcp:0' else ''
        with patch.object(host.socket,'create_connection',return_value=Connection()):
            properties,wire=host.ipc_properties(adb,'/data/user/0/test/cache/probe.sock')
        self.assertEqual(properties['vid'],dict(error='success',data='no'))
        self.assertEqual(properties['video-dec-params']['error'],'property unavailable')
        self.assertEqual(len(wire),5)
        self.assertEqual(commands[-1],('forward','--remove','tcp:18084'))
        with patch.object(host.socket,'create_connection',side_effect=OSError('unavailable')):
            properties,wire=host.ipc_properties(adb,'/data/user/0/test/cache/probe.sock')
        self.assertEqual(properties,{})
        self.assertIn('COLLECTOR_ERROR:',wire[-1])

    def test_s00d_rule_inventory_rejects_absence_and_recomputes_observations(self):
        from matrix_evidence import Evidence
        rules=json.loads((matrix.TOOL/'matrix_rules.json').read_text(encoding='utf-8'))
        inventory=json.loads((matrix.TOOL/'s00d_rules_inventory.json').read_text(encoding='utf-8'))
        with tempfile.TemporaryDirectory(dir=matrix.TOOL) as folder:
            path=Path(folder)/'unit-s00d.json'
            for row,idents in inventory['added'].items():
                for spec in rules[row]['requires']:
                    if spec.get('ident') not in idents:continue
                    clauses=spec.get('assertions')
                    self.assertTrue(clauses,msg=spec)
                    path.write_text(json.dumps(dict(status='done',records=[])))
                    self.assertEqual(Evidence(folder,'unit-').check(**{k:v for k,v in spec.items() if k!='kind'})[0],
                                     'BLOCKED',msg=spec)
                    record=dict(kind='CHECK',id=spec['ident'],**{'pass':True})
                    path.write_text(json.dumps(dict(status='done',records=[record])))
                    self.assertEqual(Evidence(folder,'unit-').check(**{k:v for k,v in spec.items() if k!='kind'})[0],
                                     'BLOCKED',msg=spec)
            for row in inventory['complete']:
                self.assertFalse(any(c.get('ident','').endswith('.coverage1') for c in rules[row]['requires']))

    def test_s00d_public_rule_predicates_against_captured_offline_checks(self):
        from matrix_evidence import Evidence
        rules=json.loads((matrix.TOOL/'matrix_rules.json').read_text(encoding='utf-8'))
        inventory=json.loads((matrix.TOOL/'s00d_rules_inventory.json').read_text(encoding='utf-8'))
        captured={r['id']:r for r in map(json.loads,(matrix.TOOL/'testdata/s00d-offline-checks.jsonl').read_text(encoding='utf-8').splitlines())}
        compared=set()
        for row,idents in inventory['added'].items():
            for spec in rules[row]['requires']:
                ident=spec.get('ident')
                if ident not in idents or ident not in captured:continue
                original=captured[ident]
                self.assertEqual(Evidence.assertions(original,spec['assertions']),'PASS',msg=ident)
                compared.add(ident)
                for clause in spec['assertions']:
                    corrupt=copy.deepcopy(original)
                    parts=clause['field'].split('.')
                    target=corrupt
                    for part in parts[:-1]:target=target[int(part)] if isinstance(target,list) else target[part]
                    key=int(parts[-1]) if isinstance(target,list) else parts[-1]
                    del target[key]
                    # Removing an indexed list item can also make a different
                    # observed list; neither outcome is allowed to pass.
                    self.assertIn(Evidence.assertions(corrupt,spec['assertions']),('BLOCKED','FAIL'),msg=(ident,clause))
        self.assertGreater(len(compared),130)

    def test_s00d_widget_checks_recompute_the_real_producer_log(self):
        from matrix_evidence import Evidence
        from coverage_s00d_offline import records_from_output
        rules=json.loads((matrix.TOOL/'matrix_rules.json').read_text(encoding='utf-8'))
        # A small raw fixture has the same shape as the real widget producer;
        # changing pass alone cannot make increasing/rightward text scroll pass.
        row=dict(kind='CHECK',id='C6.scroll',actual=[True,True],
                 numbers=dict(beforeX=100,afterX=70,trackA=0,trackB=28),**{'pass':True})
        spec=next(c for c in rules['C6']['requires'] if c.get('ident')=='C6.scroll')
        args={k:v for k,v in spec.items() if k!='kind'}
        with tempfile.TemporaryDirectory(dir=matrix.TOOL) as folder:
            p=Path(folder)/'unit-widgets.json'
            def verdict(record):
                p.write_text(json.dumps(dict(status='done',records=[record])))
                return Evidence(folder,'unit-').check(**args)[0]
            self.assertEqual(verdict(row),'PASS')
            row['numbers']['afterX']=120
            self.assertEqual(verdict(row),'FAIL')
            del row['numbers']['beforeX']
            self.assertEqual(verdict(row),'BLOCKED')
            self.assertEqual(records_from_output('MATRIX_RECORD '+json.dumps(row)),[row])
            p.write_text(json.dumps(dict(status='error',records=[row])))
            self.assertEqual(Evidence(folder,'unit-').check(**args)[0],'BLOCKED')

    def test_s00d_native_samples_require_raw_fields_and_reject_false_counters(self):
        from matrix_evidence import Evidence
        rules=json.loads((matrix.TOOL/'matrix_rules.json').read_text(encoding='utf-8'))
        def clauses(row,ident):return next(c['assertions'] for c in rules[row]['requires'] if c.get('ident')==ident)
        sample=dict(numbers=dict(count=1,clients=['libmpv','mova_qoe_12']))
        cs=clauses('N13','N13.clients.precise')
        self.assertEqual(Evidence.assertions(sample,cs),'PASS')
        sample['numbers']['clients']=['libmpv']
        self.assertEqual(Evidence.assertions(sample,cs),'FAIL')
        del sample['numbers']['clients']
        self.assertEqual(Evidence.assertions(sample,cs),'BLOCKED')
        sample=dict(numbers=dict(requestCount=2,nativeHeaders='X-S00D: one',requests=['one','one'],
                    lavf='probesize=32768,protocol_whitelist=known'))
        cs=clauses('C17','C17.headers.one')
        self.assertEqual(Evidence.assertions(sample,cs),'PASS')
        sample['numbers']['requests'][1]='wrong'
        self.assertEqual(Evidence.assertions(sample,cs),'FAIL')
        sample=dict(numbers=dict(coveredThroughEnd=True,coveredThroughStart=True,frameCount=3,gapCount=2,frameGapsUs=[16000,99999]))
        cs=clauses('F13','F13.disposeFrames')
        self.assertEqual(Evidence.assertions(sample,cs),'PASS')
        sample['numbers']['frameGapsUs']=[100000]
        self.assertEqual(Evidence.assertions(sample,cs),'FAIL')
        sample['numbers']['frameGapsUs']=None
        self.assertEqual(Evidence.assertions(sample,cs),'BLOCKED')
        before=dict(rss=100,threads=4,handles=5,cpuTicks=10)
        after=dict(rss=110,threads=4,handles=5,cpuTicks=15)
        sample=dict(numbers=dict(before=before,after=after,created=3,engineCount=3))
        cs=clauses('F13','F13.resources.20')
        self.assertEqual(Evidence.assertions(sample,cs),'PASS')
        sample['numbers']['created']=4
        self.assertEqual(Evidence.assertions(sample,cs),'FAIL')
        sample['numbers']['created']=3;after['handles']=None
        self.assertEqual(Evidence.assertions(sample,cs),'BLOCKED')
        sample=dict(numbers=dict(videoCount=1,widgetFit='contain',stateFit='contain',
                    videoWidth=640,videoHeight=360,viewportWidth=400,viewportHeight=240,
                    sourceWidth=640,sourceHeight=360,destinationWidth=400,destinationHeight=225))
        cs=clauses('A11','A11.render.contain')
        self.assertEqual(Evidence.assertions(sample,cs),'PASS')
        sample['numbers']['destinationHeight']=250
        self.assertEqual(Evidence.assertions(sample,cs),'FAIL')

    def test_s00d_receipts_compare_every_field_and_keep_engine_identity_separate(self):
        from matrix_evidence import Evidence
        rules=json.loads((matrix.TOOL/'matrix_rules.json').read_text(encoding='utf-8'))
        specs=[s for s in rules['A2']['requires'] if s.get('ident','').endswith('.receipt')]
        self.assertEqual({s['ident'] for s in specs},{'A2.engine.receipt','A2.cutover.receipt'})
        fields={c['field'].split('.',1)[1] for c in specs[0]['assertions'] if c['field'].startswith('actual.')}
        self.assertTrue({'position','intent','renderEpoch','sourceIndex','buffering','width','height'}<=fields)
        for spec in specs:
            actual={f:0 for f in fields};actual['quality']=None;actual['qualities']=[]
            sample=dict(actual=actual,expected=copy.deepcopy(actual),numbers=dict(fields=len(fields)))
            self.assertEqual(Evidence.assertions(sample,spec['assertions']),'PASS')
            for field in fields:
                corrupted=copy.deepcopy(sample);corrupted['actual'][field]='bad'
                self.assertEqual(Evidence.assertions(corrupted,spec['assertions']),'FAIL',msg=field)
                missing=copy.deepcopy(sample);del missing['actual'][field]
                self.assertEqual(Evidence.assertions(missing,spec['assertions']),'BLOCKED',msg=field)

    def test_s00c_checks_recompute_arithmetic_and_require_readbacks(self):
        from matrix_evidence import Evidence
        with tempfile.TemporaryDirectory(dir=matrix.TOOL) as folder:
            out=Path(folder)
            path=out/'unit-source.json'
            row=dict(kind='CHECK',id='C4.abrDown',numbers=dict(before=100,after=80),**{'pass':True})
            def verdict():
                path.write_text(json.dumps(dict(status='done',records=[row])))
                return Evidence(out,'unit-').check('C4.abrDown',assertions=[
                    dict(field='numbers.after',op='lt',other='numbers.before')])[0]
            self.assertEqual(verdict(),'PASS')
            row['numbers']['after']=120
            self.assertEqual(verdict(),'FAIL')
            del row['numbers']['before']
            self.assertEqual(verdict(),'BLOCKED')
            row.update(numbers=dict(pinned=None),**{'pass':None})
            path.write_text(json.dumps(dict(status='done',records=[row])))
            self.assertEqual(Evidence(out,'unit-').check('C4.abrDown',assertions=[
                dict(field='numbers.pinned',op='eq',value=True)])[0],'BLOCKED')

    def test_completed_command_is_independent_of_an_unrelated_suite_error(self):
        manifest=dict(ids=['A24'],manual=[],batches=[dict(id='existing-pages',covers=['A24'])])
        explicit=dict(A24=dict(status='PASS',evidence='complete cutover command',evidence_only=True))
        results={'existing-pages':dict(kind='HARNESS',driver='subtitles.driver.log')}
        self.assertEqual(matrix.make_rows(manifest,results,explicit)[0]['status'],'PASS')
        self.assertEqual(results['existing-pages']['kind'],'HARNESS')
        explicit['A24']['status']='BLOCKED'
        self.assertEqual(matrix.make_rows(manifest,results,explicit)[0]['status'],'BLOCKED')

    def test_retired_broadcast_assertion_cannot_poison_sequence_replacement(self):
        from matrix_evidence import reduce_evidence
        with tempfile.TemporaryDirectory(dir=matrix.TOOL) as folder:
            out=Path(folder)
            records=[dict(kind='CHECK',id='A1.broadcast',**{'pass':False}),
                     dict(kind='CHECK',id='A1.events.sequence',**{'pass':True})]
            (out/'unit-basic.json').write_text(json.dumps(dict(status='done',records=records)))
            rules={'A1':dict(requires=[dict(kind='check',ident='A1.events.sequence')]),
                   '_invalid_checks':{'A1.broadcast':'retired requirement'}}
            manifest=dict(ids=['A1'],manual=[])
            self.assertEqual(reduce_evidence(manifest,out,'unit-',rules)['A1']['status'],'PASS')

    def test_structured_log_records_require_completion(self):
        from matrix_evidence import Evidence
        with tempfile.TemporaryDirectory(dir=matrix.TOOL) as folder:
            path=Path(folder)/'unit-keepalive-core.log'
            row=dict(kind='CHECK',id='S6.publicFallback',numbers=dict(phase='fallback'),**{'pass':True})
            content='[STANDBY] MATRIX_RECORD '+json.dumps(row)+'\n'
            path.write_text(content)
            self.assertEqual(Evidence(folder,'unit-').check('S6.publicFallback')[0],'BLOCKED')
            path.write_text(content+'AUTORUN DONE\n')
            value,detail=Evidence(folder,'unit-').check('S6.publicFallback')
            self.assertEqual(value,'PASS')
            self.assertIn('line[1]',detail)

    def test_keepalive_grace_is_unresolved_and_bad_native_readback_fails(self):
        from matrix_evidence import Evidence
        with tempfile.TemporaryDirectory(dir=matrix.TOOL) as folder:
            path=Path(folder)/'unit-keepalive-core.log'
            sample='S1 gop=25f hold=3s phase=holding mode=muted resume=5001ms signal=grace from=muted decodedProp=158ms vid=1 mute=no\n'
            path.write_text(sample*9+'AUTORUN DONE\n')
            self.assertEqual(Evidence(folder,'unit-').keepalive_wake()[0],'BLOCKED')
            path.write_text(sample.replace('signal=grace','signal=size')*9+'AUTORUN DONE\n')
            self.assertEqual(Evidence(folder,'unit-').keepalive_wake()[0],'PASS')
            path.write_text(sample.replace('mute=no','mute=yes')*9+'AUTORUN DONE\n')
            self.assertEqual(Evidence(folder,'unit-').keepalive_wake()[0],'FAIL')

    def test_gap_named_checks_require_case_end_and_preserve_original_index(self):
        from coverage_gap import canonical_checks
        rows=[dict(kind='CHECK',case='gap:open',data=dict(id='U2.tree.default',**{'pass':True})),
              dict(kind='CHECK',case='gap:done',data=dict(id='U2.tree.mini',**{'pass':True})),
              dict(kind='END',case='gap:done'),
              dict(kind='CHECK',case='gap:error',data=dict(id='U2.tree.douyin',**{'pass':True})),
              dict(kind='ERROR',case='gap:error'),dict(kind='END',case='gap:error')]
        checks=canonical_checks(rows)
        self.assertEqual([r['id'] for r in checks],['U2.tree.mini'])
        self.assertEqual(checks[0]['originGapIndex'],1)

    def test_native_window_parsers_fail_closed_and_scope_pip_to_target(self):
        from coverage_s00c import window_values,pinned_value,close_bounds,observation,PACKAGE
        window='mDisplayFrames=DisplayFrames w=2400 h=1080 r=1\n'+\
            'InsetsSource: type=statusBars frame=[0,0][2400,90] visible=false\n'+\
            'InsetsSource: type=navigationBars frame=[0,1000][2400,1080] visible=false\n'+\
            'mCurrentFocus=Window{123 '+PACKAGE+'/MainActivity}\n'
        values=window_values(window)
        self.assertEqual(values,dict(width=2400,height=1080,rotation=1,status=False,navigation=False,focused=True))
        self.assertIsNone(observation('A14',{},dict(status=False))['pass'])
        self.assertIsNone(observation('A14',dict(status=False),dict(status=None))['pass'])
        self.assertFalse(observation('A14',dict(status=True),dict(status=False))['pass'])
        self.assertNotIn('status',window_values(window+'InsetsSource: type=statusBars visible=true\n'))
        self.assertIsNone(pinned_value('Task{123 A=other.app mode=pinned}'))
        self.assertFalse(pinned_value('Task{123 A='+PACKAGE+' mode=fullscreen}'))
        self.assertTrue(pinned_value('Task{123 A='+PACKAGE+' mode=pinned}'))
        xml='<hierarchy><node package="other.app" content-desc="Close" bounds="[0,0][20,20]"/></hierarchy>'
        self.assertIsNone(close_bounds(xml))
        self.assertEqual(close_bounds(xml.replace('other.app','com.android.systemui')),[10,10])
        self.assertIsNone(close_bounds('broken'))

    def test_evidence_reducer_failure_missing_alias_and_no_ledger(self):
        from matrix_evidence import reduce_evidence
        with tempfile.TemporaryDirectory(dir=matrix.TOOL) as folder:
            out=Path(folder)
            m=dict(ids=['A6','A7','E.MovaSwapChange'],manual=[])
            rules={'A6':dict(requires=[dict(kind='check',ident='A6.pause')]),
                   'A7':dict(requires=[dict(kind='check',ident='A7.seek')],missing=['seekBy']),
                   'E.MovaSwapChange':dict(requires=[dict(kind='event',name='MovaSwapChange')])}
            (out/'unit-ledger.json').write_text(json.dumps(dict(rows=[dict(id='A6',status='PASS')])))
            records=[dict(kind='CHECK',id='A6.pause',**{'pass':False}),dict(kind='BEGIN'),
                     dict(kind='CHECK',id='A6.pause',**{'pass':True}),
                     dict(kind='CHECK',id='A7.seek',**{'pass':False}),
                     dict(kind='EVENT',ms=123,event='MovaCutoverChange',payload={},state={})]
            (out/'unit-test.json').write_text(json.dumps(dict(status='done',records=records)))
            v=reduce_evidence(m,out,'unit-',rules)
            self.assertEqual(v['A6']['status'],'PASS')
            self.assertEqual(v['A7']['status'],'FAIL')
            self.assertEqual(v['E.MovaSwapChange']['status'],'PASS')
            self.assertTrue(all(r['status']=='BLOCKED' for r in reduce_evidence(m,out,'other-',rules).values()))
            records[-2]['pass']='false'
            (out/'unit-test.json').write_text(json.dumps(dict(status='done',records=records)))
            self.assertEqual(reduce_evidence(m,out,'unit-',rules)['A7']['status'],'BLOCKED')

    def test_evidence_requires_sources_and_boolean_checks(self):
        from matrix_evidence import Evidence
        with tempfile.TemporaryDirectory(dir=matrix.TOOL) as folder:
            out=Path(folder)
            (out/'unit-a.json').write_text(json.dumps(dict(status='done',records=[dict(kind='CHECK',id='A4',**{'pass':True})])))
            ev=Evidence(out,'unit-')
            self.assertEqual(ev.check('A4',sources=['a.json','b.json'])[0],'BLOCKED')
            (out/'unit-b.json').write_text(json.dumps(dict(status='done',records=[dict(kind='CHECK',id='A4',**{'pass':False})])))
            self.assertEqual(Evidence(out,'unit-').check('A4',sources=['a.json','b.json'])[0],'FAIL')
            (out/'unit-b.json').write_text('{broken')
            ev=Evidence(out,'unit-')
            self.assertEqual(ev.check('A4',sources=['a.json','b.json'])[0],'BLOCKED')
            self.assertTrue(ev.errors)

    def test_cp0_completion_and_batch_registration(self):
        result=dict(run_id='unit',group='pod2',completed=True,harness=[],records=[],
                    verdicts=[dict(case='CP0.pod2.ad2.0',status='PASS')])
        self.assertEqual(matrix.cp0_result_kind(result,'unit','pod2',0),'OK')
        result['harness']=['script error']
        self.assertEqual(matrix.cp0_result_kind(result,'unit','pod2',0),'HARNESS')
        with self.assertRaises(ValueError):matrix.cp0_result_kind(result,'old','pod2',0)
        names={b['id'] for b in self.manifest['batches']}
        self.assertTrue({'cp0-p02','cp0-pod2','cp0-bgpause','cp0-pauseload','cp0-timeshift','cp0-pageview'}<=names)

    def test_rate_sequence_uses_actual_events_and_hls_requires_modes(self):
        from matrix_evidence import Evidence
        with tempfile.TemporaryDirectory(dir=matrix.TOOL) as folder:
            out=Path(folder)
            for mode in ('basic','basic-cutover'):
                records=[dict(kind='RATE',input=v,actual=99) for v in (.5,1,1.5,2,-1,0)]
                records += [dict(kind='EVENT',event='MovaRateChange',payload=dict(value=v)) for v in (.5,1,1.5,2,.25)]
                (out/('unit-rerun-batch15-'+mode+'.json')).write_text(json.dumps(dict(status='done',records=records)))
            ev=Evidence(out,'unit-')
            self.assertEqual(ev.rate_sequence()[0],'PASS')
            ev.records = [(r,p) for r,p in ev.records if r.get('payload',{}).get('value') != 1.5]
            self.assertEqual(ev.rate_sequence()[0], 'FAIL')
            (out/'unit-hls.json').write_text(json.dumps(dict(status='done',records=[dict(kind='HLS_RESULT',cutover=False,paused=False,**{'pass':True})])))
            self.assertEqual(Evidence(out,'unit-').hls(variants=[dict(cutover=True,paused=False)])[0],'BLOCKED')

    def test_cp0_requires_all_measurements_without_product_threshold(self):
        from coverage_cp0 import validate_checks
        read=dict(path='http://local/ad2.mp4',timePosMs=40)
        numbers=dict(waitForAdReadyPre=True,epoch0=0,firstEpochDelta=1,firstFrame1Us=10,
                     firstFrame2Us=110,firstFrame1={},firstFrame2={},epoch1=1,epoch2=2,
                     epochDelta=1,first=read,second=read,firstFrameGapUs=100,doneEvents=[1])
        checks=[dict(id=f'CP0.pod2.{v}.ad2.0',status='PASS',numbers=copy.deepcopy(numbers),
                     **{'pass':True}) for v in ('wait','nowait')]
        self.assertEqual(validate_checks('pod2',1,checks),[])
        self.assertTrue(validate_checks('pod2',2,checks))
        self.assertTrue(validate_checks('pod2',1,checks[:1]))
        del checks[0]['numbers']['second']
        self.assertTrue(validate_checks('pod2',1,checks))

    def test_rule_and_raw_schema_errors_block_without_crashing(self):
        from matrix_evidence import reduce_evidence
        with tempfile.TemporaryDirectory(dir=matrix.TOOL) as folder:
            out=Path(folder);m=dict(ids=['A6'],manual=[])
            rules={'A6':dict(requires=[dict(kind='not_a_validator')])}
            self.assertEqual(reduce_evidence(m,out,'unit-',rules)['A6']['status'],'BLOCKED')
            (out/'unit-invalid.json').write_text(json.dumps(dict(records=[None])))
            rules={'A6':dict(requires=[dict(kind='check',ident='A6.pause')])}
            verdicts=reduce_evidence(m,out,'unit-',rules)
            result=verdicts['A6']
            self.assertEqual(result['status'],'BLOCKED')
            self.assertIn('缺 CHECK',result['evidence'])
            self.assertIn('records 含非对象记录',verdicts.evidence_errors[0])

    def test_cp0_events_cannot_poison_legacy_event_verdicts(self):
        from matrix_evidence import Evidence
        with tempfile.TemporaryDirectory(dir=matrix.TOOL) as folder:
            out=Path(folder)
            event=dict(kind='EVENT',ms=100,event='MovaDurationChange',payload=dict(duration=9),state=dict(duration=9))
            (out/'unit-legacy.json').write_text(json.dumps(dict(status='done',records=[event])))
            event=dict(kind='EVENT',us=100,event='MovaDurationChange',payload=dict(duration=9),state=dict(durationMs=9))
            (out/'unit-cp0-pod2.json').write_text(json.dumps(dict(completed=True,records=[event])))
            self.assertEqual(Evidence(out,'unit-').event('MovaDurationChange')[0],'PASS')

    def test_cp0_child_mapping_ownership(self):
        with tempfile.TemporaryDirectory(dir=matrix.TOOL) as folder:
            out=Path(folder)
            driver=object.__new__(matrix.Driver)
            driver.out=out;driver.prefix='matrix-unit-';driver.mappings=[];driver.results={};driver.env={}
            driver.args=argparse.Namespace(run_id='unit');driver.screen=lambda:None;driver.note=lambda *args:None
            path=out/'result.json'
            path.write_text(json.dumps(dict(run_id='unit',group='pod2',completed=True,harness=[],records=[],
                           verdicts=[dict(case='CP0.pod2.ad2.0',status='PASS')])))
            job=dict(id='cp0-pod2',description='measurement',why='record evidence',timeout=5,
                     native_driver=True,cp0_driver=True,result_path=str(path),argv=[sys.executable,'unused.py'])
            from unittest.mock import Mock
            child=Mock();child.wait.return_value=0
            with patch.object(matrix.subprocess,'Popen',return_value=child), patch.object(matrix,'subcheck_observations',return_value=[]):
                self.assertTrue(driver.batch(job))
            self.assertEqual(driver.mappings,[])

    def test_real_manifest(self):
        """Require exactly the canonical 135 IDs / 必须覆盖规范的135编号。"""
        self.assertEqual(matrix.validate_manifest(self.manifest),[])
        self.assertEqual(len(self.manifest['ids']),135)

    def test_extended_ids_do_not_change_legacy_coverage(self):
        """§10/H extensions validate independently of the canonical 135 IDs."""
        batch = self.manifest['batches'][-1]
        batch['covers_ext'] = ['G1.1', 'G2.3', 'S16', 'P21', 'A35', 'H1', 'H78']
        self.assertEqual(matrix.validate_manifest(self.manifest), [])
        batch['covers_ext'].append('H79')
        self.assertTrue(any('未知扩展' in e for e in matrix.validate_manifest(self.manifest)))
        batch['covers_ext'] = ['G99.9']
        self.assertTrue(any('未知扩展' in e for e in matrix.validate_manifest(self.manifest)))
        batch['covers_ext'] = 'H28'
        self.assertTrue(any('covers_ext' in e for e in matrix.validate_manifest(self.manifest)))

    def test_gap_completion_distinguishes_product_and_harness(self):
        result=dict(run_id='unit',group='random',completed=True,harness=[],
                    verdicts=[dict(case='gap:G4.1.seed',status='FAIL')])
        self.assertEqual(matrix.gap_result_kind(result,'unit','random',1),'OK')
        result['verdicts'][0]['status']='BLOCKED'
        self.assertEqual(matrix.gap_result_kind(result,'unit','random',1),'OK')
        result['completed']=False
        self.assertEqual(matrix.gap_result_kind(result,'unit','random',1),'BLOCKED')
        result['harness']=['uncaught exception']
        self.assertEqual(matrix.gap_result_kind(result,'unit','random',1),'HARNESS')
        self.assertEqual(matrix.gap_result_kind(result,'unit','random',2),'HARNESS')
        with self.assertRaises(ValueError):matrix.gap_result_kind(result,'old','random',0)
        result['verdicts'][0]['status']='INVALID'
        with self.assertRaises(ValueError):matrix.gap_result_kind(result,'unit','random',0)

    def test_skin_batch_wired_to_driver_group(self):
        """gap-skin covers the S-ids it runs and targets a group the driver accepts."""
        batch=next(b for b in self.manifest['batches'] if b['id']=='gap-skin')
        self.assertTrue({'S1','S7','S9','S12','S13','S14'}<=set(batch['covers_ext']))
        self.assertFalse(batch['fast'])
        self.assertTrue(batch['screen_on'] and batch['native_driver'])
        source=ast.parse((matrix.TOOL/'coverage_gap.py').read_text(encoding='utf-8'))
        choices=[a.value for n in ast.walk(source) if isinstance(n,ast.Call)
                 and isinstance(n.func,ast.Attribute) and n.func.attr=='add_argument'
                 and n.args and isinstance(n.args[0],ast.Constant) and n.args[0].value=='group'
                 for kw in n.keywords if kw.arg=='choices' for a in kw.value.elts]
        self.assertIn(batch['argv'][2],choices)
        flags={a.value for n in ast.walk(source) if isinstance(n,ast.Call)
               and isinstance(n.func,ast.Attribute) and n.func.attr=='add_argument'
               for a in n.args if isinstance(a,ast.Constant) and str(a.value).startswith('--')}
        self.assertIn('--skins',flags)

    def test_native_driver_requires_owned_metadata(self):
        batch=next(b for b in self.manifest['batches'] if b.get('native_driver'))
        del batch['result_path']
        self.assertTrue(any('native_driver' in e for e in matrix.validate_manifest(self.manifest)))

    def test_missing_coverage(self):
        """Reject uncovered and unknown IDs / 拒绝遗漏和未知编号。"""
        for b in self.manifest['batches']:
            b['covers']=[i for i in b['covers'] if i!='A1']
        self.assertTrue(any('覆盖缺失' in e for e in matrix.validate_manifest(self.manifest)))
        self.manifest['batches'][0]['covers'].append('A999')
        self.assertTrue(any('未知' in e for e in matrix.validate_manifest(self.manifest)))

    def test_duplicate_and_dependency(self):
        """Reject duplicate names and forward dependencies / 拒绝重名和前向依赖。"""
        self.manifest['batches'][1]['id']=self.manifest['batches'][0]['id']
        self.manifest['batches'][0]['dependencies'].append('missing')
        errors=matrix.validate_manifest(self.manifest)
        self.assertTrue(any('重复' in e for e in errors))
        self.assertTrue(any('依赖' in e for e in errors))

    def test_invalid_commands(self):
        """Reject missing scripts, shell strings and flags / 拒绝缺脚本、shell字符串及错参数。"""
        for command in ('python tool.py', ['{python}','{tool}/absent.py'], ['{python}','{tool}/coverage_device.py','--bad-option']):
            m=copy.deepcopy(self.manifest)
            m['batches'][0]['argv']=command
            self.assertTrue(matrix.validate_manifest(m))

    def test_select_only_dependencies(self):
        """Keep launch dependencies in manifest order / 按清单顺序补启动依赖。"""
        jobs=matrix.select_batches(self.manifest,'native-inputs')
        self.assertEqual([b['id'] for b in jobs],['api-launch','native-inputs'])

    def test_select_from_fast_and_unknown(self):
        """Check continuation, fast intersection and unknown names / 检查续跑、fast交集和未知批次。"""
        names=[b['id'] for b in matrix.select_batches(self.manifest,start='final-api',fast=True)]
        self.assertIn('api-launch',names)
        self.assertIn('final-api',names)
        self.assertNotIn('api',names)
        with self.assertRaises(ValueError):matrix.select_batches(self.manifest,'unknown')
        with self.assertRaises(ValueError):matrix.select_batches(self.manifest,start='unknown')

    def test_compare_all_transitions(self):
        """Test each comparison category / 测所有对比类别。"""
        before={'rows':[dict(id=i,status=s) for i,s in [('a','PASS'),('b','FAIL'),('c','FAIL'),('d','BLOCKED'),('e','PASS'),('f','BLOCKED')]]}
        rows=[dict(id=i,status=s) for i,s in [('a','FAIL'),('b','PASS'),('c','FAIL'),('d','BLOCKED'),('e','BLOCKED'),('f','PASS')]]
        result=matrix.compare_ledgers(rows,before)
        self.assertEqual(result,dict(zip(('新增失败','已修复','仍失败','仍阻塞','新增阻塞','已解除阻塞'),[['a'],['b'],['c'],['d'],['e'],['f']])))

    def test_no_inherited_pass(self):
        """Never inherit old PASS, or upgrade a failed harness / 不继承PASS或掩盖验证器失败。"""
        rows=matrix.make_rows(self.manifest,{}, {'A4':dict(status='PASS',evidence='old')})
        self.assertEqual(len(rows),135)
        self.assertTrue(all(r['status']=='BLOCKED' for r in rows))
        results={b['id']:dict(kind='OK',driver='fresh.driver.log') for b in self.manifest['batches']}
        explicit={'A4':dict(status='FAIL',evidence='fresh CHECK')}
        rows=matrix.make_rows(self.manifest,results,explicit)
        self.assertEqual(next(r for r in rows if r['id']=='A4')['status'],'FAIL')
        results['api']['kind']='HARNESS'
        self.assertEqual(next(r for r in matrix.make_rows(self.manifest,results,explicit) if r['id']=='A4')['status'],'BLOCKED')

    def test_markdown_summary(self):
        """Render all rows, comparison and harness diagnostics / 渲染全台账、对比与验证器错误。"""
        rows=matrix.make_rows(self.manifest,{}, {})
        text=matrix.render_summary('unit',rows,{'新增失败':[]},{'api':dict(kind='HARNESS',error='timeout',driver='api.driver.log')},'baseline.json')
        self.assertEqual(len(re.findall(r'^\| (?:[ACUFN]\d+|E\.\w+|E[12]) \| BLOCKED \|',text,re.M)),135)
        self.assertIn('timeout',text)
        self.assertIn('最小复现',text)

    def test_screen_markers(self):
        """Reject missing, locked and sleeping screen states / 拒绝缺标记、锁屏和灭屏。"""
        self.assertTrue(matrix.is_unlocked('isKeyguardShowing=false mScreenOnFully=true'))
        for text in ('','isKeyguardShowing=true mScreenOnFully=true','mScreenOnFully=true','isKeyguardShowing=false mScreenOnFully=false'):
            self.assertFalse(matrix.is_unlocked(text))

    def test_media_fixtures_are_seeded(self):
        """Isolated media dir gets truncated/vod/subtitle fixtures / 隔离媒体目录补入静态夹具。"""
        with tempfile.TemporaryDirectory() as tmp:
            seeded=matrix_compat.seed_media(tmp,'matrix-unit-')
            target=Path(tmp)/'matrix-unit-coverage_media'
            for name in seeded:
                self.assertTrue((target/name).is_file())
            self.assertEqual(matrix_compat.seed_media(tmp,'matrix-unit-'),[])  # 幂等
            if (matrix.TOOL/'coverage_media/truncated.mp4').is_file():
                self.assertIn('truncated.mp4',seeded)

    def test_gap_screen_runs_last_and_locks(self):
        """The screen-locking batch must be last / 锁屏批次必须排在最后。"""
        last=self.manifest['batches'][-1]
        self.assertEqual(last['id'],'gap-screen')
        self.assertTrue(last.get('locks_screen'))

    def test_compat_paths_are_isolated(self):
        """Transform path constants without changing logic / 只改路径而不改判定。"""
        out=matrix.TOOL/'coverage_evidence/matrix-unit'
        source="O=ROOT/'example/tool/coverage_evidence'\nD=ROOT/'doc/plans/old.md'\npass_value=False\n"
        tree=matrix_compat.transform(source,str(matrix.TOOL/'legacy.py'),out,'matrix-unit-')
        values=[n.value for n in ast.walk(tree) if isinstance(n,ast.Constant)]
        self.assertIn(str(out),values)
        self.assertIn(str(out/'matrix-unit-checkpoints.md'),values)
        self.assertIn(False,values)

    def test_existing_full_id_checks(self):
        """Require both engines and trim accumulated records / 要求两实现并切除累计旧记录。"""
        with tempfile.TemporaryDirectory(dir=matrix.TOOL) as folder:
            out=Path(folder)
            records=[dict(kind='CHECK',id='A4',**{'pass':False}),dict(kind='BEGIN'),dict(kind='CHECK',id='A4',**{'pass':True})]
            for suffix in ('rerun-batch15-basic.json','rerun-batch15-basic-cutover.json'):
                (out/('matrix-unit-'+suffix)).write_text(json.dumps(dict(records=records)),encoding='utf-8')
            verdicts=matrix.existing_verdicts(out,'matrix-unit-')
            self.assertEqual(verdicts['A4']['status'],'PASS')
            self.assertNotIn('A22',verdicts)
            (out/'matrix-unit-rerun-batch15-basic.json').unlink()
            self.assertEqual(matrix.existing_verdicts(out,'matrix-unit-'),{})

    def test_subitem_verdicts(self):
        """子项独立收口，失败传播且不把局部通过升级为整项通过。"""
        with tempfile.TemporaryDirectory() as folder:
            out = Path(folder)
            path = out/'unit-check.json'
            path.write_text(json.dumps(dict(records=[
                dict(kind='CHECK', id='A6.old', **{'pass': False}),
                dict(kind='BEGIN'),
                dict(kind='CHECK', id='A6.pause', **{'pass': True}),
                dict(kind='CHECK', id='A7.seek', **{'pass': False}),
                dict(kind='CHECK', id='A8.clamp', **{'pass': 'true'}),
            ])), encoding='utf-8')
            verdicts = matrix.subitem_verdicts(out, 'unit-')
            self.assertEqual(verdicts['A6']['status'], 'BLOCKED')
            self.assertEqual(verdicts['A6']['subitems'][0]['status'], 'PASS')
            self.assertEqual(verdicts['A7']['status'], 'FAIL')
            self.assertEqual(verdicts['A8']['subitems'][0]['status'], 'BLOCKED')
            self.assertEqual(matrix.subitem_verdicts(out, 'other-'), {})

    def test_offline_modes_have_no_side_effects(self):
        """Fail tests on any attempted subprocess/socket/write / 任何进程、端口或写入即失败。"""
        for args in (['--check'],['--list'],['--dry-run','--fast','--run-id','unit']):
            with self.subTest(args=args), patch.object(matrix,'Driver',side_effect=AssertionError('device')), \
                 patch.object(matrix.subprocess,'Popen',side_effect=AssertionError('process')), \
                 patch.object(matrix.socket,'socket',side_effect=AssertionError('socket')), \
                 patch.object(Path,'write_text',side_effect=AssertionError('write')), \
                 contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(matrix.main(args),0)

    def test_compat_python_children_and_record(self):
        """Exercise real pure-Python children, namespacing and existing update.

        仅执行合成 Python 子进程，检查隔离路径和已有 update 判定写入。
        """
        with tempfile.TemporaryDirectory(dir=matrix.TOOL) as folder:
            work=Path(folder)
            out=work/'evidence'
            out.mkdir()
            checkpoint=out/'matrix-unit-checkpoints.md'
            checkpoint.write_text('# unit\n\n| A4 | BLOCKED | pending |\n',encoding='utf-8')
            child=work/'child.py'
            child.write_text("from pathlib import Path\nfrom coverage_record import update\nO=Path(__file__).parent/'coverage_evidence'\n(O/'child.json').write_text('{}')\nupdate('unit',[('A4','PASS','current')],[])\n",encoding='utf-8')
            parent=work/'parent.py'
            parent.write_text("import subprocess,sys\nfrom pathlib import Path\nsubprocess.run([sys.executable,str(Path(__file__).with_name('child.py'))],check=True)\n",encoding='utf-8')
            result=subprocess.run([sys.executable,'-B',str(matrix.TOOL/'matrix_compat.py'),str(out),'matrix-unit-','unit',str(parent)],capture_output=True,text=True,
                                  env=dict(os.environ,MOVA_MATRIX_SERIAL='offline-unit'),timeout=20)
            self.assertEqual(result.returncode,0,result.stderr)
            self.assertTrue((out/'matrix-unit-child.json').exists())
            self.assertIn('| A4 | PASS | current |',checkpoint.read_text(encoding='utf-8'))
            commandlog=(out/'matrix-unit-unit.commands.driver.log').read_text(encoding='utf-8')
            self.assertIn('CALL',commandlog)
            self.assertIn('"exit": 0',commandlog)

    def test_compat_missing_child_completion_is_harness(self):
        """Catch historical child drivers that exit zero without completion.

        识别旧子脚本退出0但无完成证据的验证器错误。
        """
        with tempfile.TemporaryDirectory(dir=matrix.TOOL) as folder:
            work=Path(folder);out=work/'evidence';out.mkdir()
            child=work/'coverage_suite_device.py'
            child.write_text("print('fake offline verifier')\n",encoding='utf-8')
            parent=work/'parent.py'
            parent.write_text("import subprocess,sys\nfrom pathlib import Path\nsubprocess.run([sys.executable,str(Path(__file__).with_name('coverage_suite_device.py')),'--name','probe'],check=True)\n",encoding='utf-8')
            result=subprocess.run([sys.executable,'-B',str(matrix.TOOL/'matrix_compat.py'),str(out),'matrix-unit-','unit',str(parent)],capture_output=True,text=True,
                                  env=dict(os.environ,MOVA_MATRIX_SERIAL='offline-unit'),timeout=20)
            self.assertEqual(result.returncode,0,result.stderr)
            errors=(out/'matrix-unit-unit.harness-errors.jsonl').read_text(encoding='utf-8')
            self.assertIn('completion metadata missing',errors)

    def test_cleanup_continues_and_verifies_restoration(self):
        """Verify finally restoration order with a fake adb function only.

        使用假 adb 函数验证失败后的完整恢复，不启动任何命令。
        """
        with tempfile.TemporaryDirectory(dir=matrix.TOOL) as folder:
            driver=object.__new__(matrix.Driver)
            driver.out=Path(folder);driver.prefix='matrix-unit-';driver.log=driver.out/'driver.log'
            driver.results={};driver.saved=dict(power='7',volume='6');driver.children=[]
            driver.mappings=[('reverse',18082)]
            driver.original_mappings={'reverse':{'tcp:18082':'tcp:19000'},'forward':{}}
            calls=[]
            def fake_adb(*argv):
                """Record fake command arguments / 记录模拟命令参数。"""
                calls.append(argv)
                if argv==('shell','am','force-stop',matrix.PACKAGE):raise RuntimeError('fake force-stop failure')
                if '--get' in argv:return 'volume is 6 in range [0..20]'
                if 'get' in argv:return '7'
                return ''
            driver.adb=fake_adb
            driver.cleanup()
            self.assertIn(('shell','media','volume','--stream','3','--set','6'),calls)
            self.assertIn(('shell','settings','put','global','stay_on_while_plugged_in','7'),calls)
            self.assertIn(('reverse','tcp:18082','tcp:19000'),calls)
            self.assertEqual(driver.results['cleanup']['kind'],'HARNESS')


class Cp1Tests(unittest.TestCase):
    def test_cp1_checks_require_every_variant_and_do_not_hide_failures(self):
        from coverage_cp1 import validate_checks
        rows=[dict(id=f'CP1.edgepause.{v}.0',status='PASS',numbers=dict(pendingAtPause=True,phase='off',pauseUs=1,atPause={},nativeSamples=[{'pause':'yes'}],after={},bufferEvents=[])) for v in ('pause','fallback')]
        self.assertEqual(validate_checks('edgepause',1,rows),[])
        self.assertTrue(validate_checks('edgepause',1,rows[:1]))
        self.assertTrue(validate_checks('edgepause',1,rows+rows[:1]))
        rows[0]['status']='BLOCKED'
        self.assertTrue(validate_checks('edgepause',1,rows))
        rows[0]['status']='FAIL'
        self.assertEqual(validate_checks('edgepause',1,rows),[]) # product FAIL remains a verdict, not missing data
        result=dict(run_id='unit',group='edgepause',harness=[],missing=[],records=[dict(kind='CHECK',**r) for r in rows],
                    completed=True,verdicts=[dict(case=r['id'],status=r['status']) for r in rows])
        self.assertEqual(matrix.cp1_result_kind(result,'unit','edgepause',1,1),'FAIL')
        rows[0]['numbers']={}
        self.assertTrue(validate_checks('edgepause',1,rows))

    def test_cp1_system_parser_requires_unambiguous_native_evidence(self):
        from cp1_sources import parse_system, parse_pss
        window='mRotation=ROTATION_0\nInsetsSource type=statusBars visible=true\nInsetsSource type=navigationBars visible=true'
        self.assertTrue(parse_system('123','mScreenBrightnessSetting=0.5\nmScreenBrightnessOverrideFromWindowManager=NaN',window)['parsed'])
        self.assertFalse(parse_system('123','mScreenBrightnessSetting=0.5\nmScreenBrightnessOverrideFromWindowManager=NaN',window+'\nmRotation=ROTATION_90')['parsed'])
        self.assertFalse(parse_system('123','OEM unsupported',window)['parsed'])
        self.assertFalse(parse_system('123','mScreenBrightnessSetting=0.5\nmScreenBrightnessOverrideFromWindowManager=NaN','rotation=0')['parsed'])
        self.assertEqual(parse_pss('  TOTAL PSS: 12345  TOTAL RSS: 54321'),12345)
        self.assertIsNone(parse_pss('unsupported OEM meminfo'))

    def test_cp1_manifest_isolated_registration(self):
        manifest=json.loads(matrix.MANIFEST.read_text(encoding='utf-8'))
        selected=matrix.select_batches(manifest,'cp1-wakeswap,cp1-pool')
        self.assertEqual([b['id'] for b in selected],['cp1-wakeswap','cp1-pool'])
        for b in selected:
            self.assertTrue(b['native_driver'] and b['cp1_driver'])
            self.assertEqual(b['covers'],[])
            self.assertEqual(b['argv'][1],'{tool}/coverage_cp1.py')
            self.assertTrue(b['result_path'].endswith(b['id']+'.json'))


class Cp1CompletionTests(unittest.TestCase):
    def test_added_batches_have_exact_formal_counts(self):
        manifest=json.loads(matrix.MANIFEST.read_text(encoding='utf-8'))
        expected={'cp1-recovery':'10','cp1-dispose120':'120','cp1-keepalive-s7s14':'5'}
        for ident,count in expected.items():
            jobs=matrix.select_batches(manifest,ident)
            self.assertEqual(len(jobs),1)
            self.assertEqual(jobs[0]['argv'][6],count)
            self.assertEqual(jobs[0]['covers'],[])
            self.assertTrue(jobs[0]['cp1_driver'])
        core=next(b for b in manifest['batches'] if b['id']=='keepalive-core')
        self.assertIn('S1,S2,S3,S6,S13,S17',core['argv'])

    def test_recovery_requires_both_variants_and_each_trial(self):
        from coverage_cp1 import validate_checks
        keys=['failures','recovered','retryCount','before','after','resumePositionDiffMs','currentQuality','fixture','seeked']
        rows=[dict(id=f'CP1.recovery.{v}.{i}',status='PASS',numbers=dict.fromkeys(keys,1))
              for v in ('resume','manual720') for i in range(10)]
        self.assertEqual(validate_checks('recovery',10,rows),[])
        self.assertTrue(validate_checks('recovery',10,rows[:-1]))
        rows[-1]['status']='FAIL'
        self.assertEqual(validate_checks('recovery',10,rows),[])
        rows[-1]['numbers'].pop('resumePositionDiffMs')
        self.assertTrue(validate_checks('recovery',10,rows))

    def test_dispose_summary_requires_ordered_rounds_and_all_pss_points(self):
        from coverage_cp1 import validate_checks
        keys=['round','firstFrames','disposeUs','frameIntervalsUs','maxFrameIntervalUs','disposed']
        rows=[dict(id=f'CP1.dispose120.round.{i}',status='PASS',numbers=dict.fromkeys(keys,1)) for i in range(120)]
        numbers=dict(rounds=[dict(round=i) for i in range(1,121)], successful=120,failedRounds=[],
                     pssSamples=[dict(round=i,pssKb=123) for i in range(20,121,20)])
        rows.append(dict(id='CP1.dispose120.summary.0',status='PASS',numbers=numbers))
        self.assertEqual(validate_checks('dispose120',120,rows),[])
        numbers['rounds'][-1]['round']=119
        self.assertTrue(validate_checks('dispose120',120,rows))
        numbers['rounds'][-1]['round']=120
        numbers['pssSamples'][-1]['pssKb']=None
        self.assertTrue(validate_checks('dispose120',120,rows))

    def test_keepalive_native_pass_never_substitutes_pixel_review(self):
        from cp1_keepalive import review_check, validate_checks
        text='os=android S7 hwdec=mediacodec-copy cycles=20\nVERDICT S7 PASS native came back'
        rows=[review_check(v,i,text,[],'raw.log') for v in ('S7','S14') for i in range(5)]
        self.assertEqual(len(rows),10)
        self.assertTrue(all(r['status']=='BLOCKED' for r in rows))
        self.assertEqual(len(validate_checks(5,rows)),10)
        self.assertIn('mediacodec-copy',rows[0]['numbers']['hwdec'])
        failed=review_check('S7',0,'os=android\nVERDICT S7 FAIL no decoded frame',[],'raw.log')
        self.assertEqual(failed['status'],'FAIL')
        self.assertFalse(failed['pass'])


class Cp2Tests(unittest.TestCase):
    def test_cp2_missing_duplicate_and_blocked_never_pass(self):
        from coverage_cp2 import validate_checks,FIELDS
        numbers=dict.fromkeys(FIELDS['pod2'],1)
        for key in ('first','second'):numbers[key]=dict(path='ad',timePosMs=1000)
        rows=[dict(kind='CHECK',id=f'CP2.pod2.{v}.{i}',status='PASS',numbers=numbers.copy()) for v in ('wait.ad2','nowait.ad2') for i in range(10)]
        self.assertEqual(validate_checks('pod2',10,rows),[])
        self.assertTrue(validate_checks('pod2',10,rows[:-1]))
        self.assertTrue(validate_checks('pod2',10,rows+[rows[0]]))
        rows[0]['status']='BLOCKED'
        self.assertTrue(validate_checks('pod2',10,rows))
        rows[0]['status']='FAIL'
        self.assertEqual(validate_checks('pod2',10,rows),[])
        result=dict(run_id='offline',group='pod2',completed=True,harness=[],missing=[],records=rows,verdicts=[dict(status='FAIL')])
        self.assertEqual(matrix.cp2_result_kind(result,'offline','pod2',1,10),'FAIL')
        rows[0]['numbers'].pop('epoch2')
        self.assertEqual(matrix.cp2_result_kind(result,'offline','pod2',1,10),'BLOCKED')

    def test_cp2_native_background_schema_required(self):
        from coverage_cp2 import validate_checks,FIELDS
        rows=[]
        for v in ('plain','view'):
            n=dict.fromkeys(FIELDS['bgowner'],[])
            n.update(before=dict(path='a',timePosMs=1000),after=dict(path='a',timePosMs=1000))
            rows.append(dict(id=f'CP2.bgowner.{v}.0',status='PASS',numbers=n))
        self.assertTrue(validate_checks('bgowner',1,rows))
        for r in rows:r['numbers']['backgroundSamples']=[dict(path='a',timePosMs=1000,pause='yes')]*2
        self.assertEqual(validate_checks('bgowner',1,rows),[])

    def test_cp2_pip_na_is_blocked_and_extra_verdicts_rejected(self):
        from cp2_alias import reduce_alias
        rows=reduce_alias('pip',1,'VERDICT V11 PASS n/a: pipSupported=false')
        self.assertEqual(rows[0]['status'],'BLOCKED')
        self.assertEqual(reduce_alias('pip',1,'VERDICT V11 PASS entered\nVERDICT V11 PASS entered')[0]['status'],'BLOCKED')
        self.assertEqual(reduce_alias('pip',1,'VERDICT V11 FAIL pauseEvents=1')[0]['status'],'FAIL')

    def test_cp2_liveedge_requires_hidden_and_actual_edge(self):
        from cp2_alias import reduce_alias
        text='VERDICT V9 PASS play=true advance=3000ms\nV9 lifecycle=[inactive,hidden,paused,resumed] play=true liveEdgeReach=true positionAdvanceOver3s=3000ms'
        self.assertEqual(reduce_alias('liveedge',1,text)[0]['status'],'PASS')
        self.assertEqual(reduce_alias('liveedge',1,text.replace('liveEdgeReach=true','liveEdgeReach=false'))[0]['status'],'FAIL')
        self.assertEqual(reduce_alias('liveedge',1,text.replace('inactive,hidden,paused,resumed','inactive,resumed'))[0]['status'],'FAIL')

    def test_cp2_rate_requires_both_variants_and_all_runs(self):
        from cp2_alias import reduce_alias
        text='\n'.join(f'RFV2|10|RESULT|{v}|run{i}|PASS|adRate settled1x=true rateAfterReturn=2.0' for v in ('V13a','V13b') for i in range(1,6))
        rows=reduce_alias('rate',5,text)
        self.assertEqual(len(rows),10)
        self.assertTrue(all(r['status']=='PASS' for r in rows))
        self.assertTrue(any(r['status']=='BLOCKED' for r in reduce_alias('rate',5,text.replace('run5','run4'))))

    def test_cp2_warmmute_requires_native_system_volume(self):
        from cp2_alias import reduce_alias
        text='\n'.join(f'VERDICT {v} PASS shadow muted' for v in ('Q13A','Q13B','Q13C'))
        self.assertTrue(all(r['status']=='BLOCKED' for r in reduce_alias('warmmute',1,text)))
        volumes=[dict(marker=m,raw='volume is 7',status='OK') for m in
            ['before','verdict:Q13A:0','verdict:Q13B:0','verdict:Q13C:0','after']]
        self.assertTrue(all(r['status']=='PASS' for r in reduce_alias('warmmute',1,text,volumes)))
        volumes[-1]['raw']='volume is 8'
        self.assertTrue(all(r['status']=='FAIL' for r in reduce_alias('warmmute',1,text,volumes)))

    def test_cp2_registered_counts_and_alias_sources(self):
        manifest=json.loads(matrix.MANIFEST.read_text(encoding='utf-8'))
        batches={b['id']:b for b in manifest['batches'] if b['id'].startswith('cp2-')}
        self.assertEqual(len(batches),14)
        for name in ('adpause','adbg','pod2','audioonly-bg'):
            self.assertEqual(batches['cp2-'+name]['argv'][6],'10')
        self.assertFalse(any('windows' in name for name in batches))
        self.assertTrue(batches['cp2-rate']['cp2_alias'])
        self.assertEqual(matrix.validate_manifest(manifest),[])


if __name__=='__main__':
    unittest.main()
