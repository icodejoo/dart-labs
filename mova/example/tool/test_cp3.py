"""Offline tests: aliases/counts, failure thresholds, HTTP positive/negative controls."""
import copy
import http.server
import json
from pathlib import Path
import sys
import tempfile
import threading
import unittest
import urllib.error
import urllib.request
from cp3_alias import resolve
from cp3_checks import validate_checks, VARIANTS, FIELDS
from cp3_f3 import judge
sys.path.insert(0,str(Path(__file__).parent/'verify_sources'))
from referer_server import Fixture, REFERER

class Cp3Tests(unittest.TestCase):
    def test_alias_snapshot_and_order(self):
        from run_matrix import MANIFEST, select_batches
        m=json.loads(MANIFEST.read_text(encoding='utf-8'))
        full=resolve(m,['cp3-full'])
        self.assertEqual(len(full),len(set(full)))
        self.assertNotIn('perf-windows',full)
        self.assertEqual(resolve(m,['cp3-f3']),['cp3-precise-normal','cp3-precise-paused','cp3-precise-cutover'])
        selected=select_batches(m,'cp3-f3')
        self.assertEqual([int(b['argv'][6]) for b in selected],[60,60,160])
        self.assertEqual(full[-3:],resolve(m,['cp3-f3']))
    def test_alias_cycle(self):
        with self.assertRaises(ValueError):resolve({'aliases':{'a':{'batches':['a']}}},['a'])
    def test_checks_reject_missing_duplicate_and_blocked(self):
        for scene,variants in VARIANTS.items():
            checks=[dict(id=f'CP3.{scene}.{v}.{i}',status='PASS',numbers={k:False for k in FIELDS[scene]}) for v,n in variants.items() for i in range(n)]
            self.assertEqual(validate_checks(scene,5,checks),[])
            self.assertTrue(validate_checks(scene,5,checks[:-1]))
            self.assertTrue(validate_checks(scene,5,checks+[checks[0]]))
            checks[0]['status']='BLOCKED'
            self.assertTrue(validate_checks(scene,5,checks))
    def test_precise_cutover_boundary_and_new_features(self):
        samples=[dict(run=i,cp0Pass=True,cp0DeltaMs=0,cp0PathCorrect=True,continuedOk=True,landed=12000,target=12000) for i in range(160)]
        data=dict(completed=True,harness=[],results=samples)
        self.assertEqual(judge('cutover',data)['status'],'PASS')
        for row in samples[:9]:row['cp0DeltaMs']=201
        self.assertEqual(judge('cutover',data)['status'],'PASS')
        samples[9]['cp0DeltaMs']=201
        self.assertEqual(judge('cutover',data)['status'],'FAIL')
        samples[9]['cp0DeltaMs']=0
        samples[0]['continuedOk']=False
        self.assertEqual(judge('cutover',data)['status'],'FAIL')
        samples[0]['continuedOk']=True
        for row in samples: row['cp0DeltaMs']=0
        samples.pop()
        self.assertEqual(judge('cutover',data)['status'],'BLOCKED')
    def test_server_checks_each_request_including_range_and_sprite(self):
        with tempfile.TemporaryDirectory() as root:
            Path(root,'a.mp4').write_bytes(b'abcdef')
            fixture=Fixture(root)
            server=http.server.ThreadingHTTPServer(('127.0.0.1',0),fixture.handler())
            thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
            base=f'http://127.0.0.1:{server.server_port}'
            opener=urllib.request.build_opener(urllib.request.ProxyHandler({}))
            try:
                for path in ('/master.m3u8','/a.mp4.vtt','/sprite.png','/a.mp4'):
                    with self.assertRaises(urllib.error.HTTPError) as error:opener.open(base+path)
                    self.assertEqual(error.exception.code,403)
                    error.exception.close()
                    req=urllib.request.Request(base+path,headers={'Referer':REFERER,'Range':'bytes=0-2'})
                    with opener.open(req) as r:self.assertTrue(r.read())
                with opener.open(base+'/stats') as r:stats=json.load(r)
                self.assertEqual(len(stats['requests']),8)
                self.assertEqual([r['status'] for r in stats['requests']],[403,200]*4)
                self.assertEqual(stats['requests'][-1]['range'],'bytes=0-2')
            finally:server.shutdown();server.server_close();thread.join()

if __name__=='__main__':unittest.main()
