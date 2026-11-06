"""No-device checks for sampling retries, time fencing and missing evidence."""
import subprocess
import json
from types import SimpleNamespace
from unittest.mock import patch
import tempfile
import unittest
from pathlib import Path
from cp2_alias import reduce_alias
from cp2_volume import VolumeSampler, sample_volume, volume_proof


class VolumeTests(unittest.TestCase):
    def rows(self):
        return [dict(marker=m, raw='volume is 7', status='OK') for m in
            ['before', 'verdict:Q13A:0', 'verdict:Q13B:0', 'verdict:Q13C:0', 'after']]

    def test_retry_transport_and_unparseable_output(self):
        responses = iter([subprocess.TimeoutExpired('fake', 1), 'daemon started', 'volume is 7'])
        def read():
            result = next(responses)
            if isinstance(result, Exception):
                raise result
            return result
        row = sample_volume('before', read, pause=lambda _: None)
        self.assertEqual(row['status'], 'OK')
        self.assertEqual(len(row['attempts']), 3)
        self.assertIn('TimeoutExpired', row['attempts'][0]['error'])

    def test_exhausted_retry_is_blocked(self):
        calls = []
        def read():
            calls.append(1)
            raise RuntimeError('transport lost')
        row = sample_volume('before', read, pause=lambda _: None)
        self.assertEqual(row['status'], 'BLOCKED')
        self.assertEqual(len(calls), 3)
        self.assertEqual(row['raw'], '')

    def test_stale_marker_never_gets_retrospective_sample(self):
        row = sample_volume('old', lambda: self.fail('must not read'), received=0, now=lambda: 4)
        self.assertEqual(row['status'], 'BLOCKED')
        self.assertEqual(row['attempts'], [])

    def test_samples_need_identities_not_total_count(self):
        rows = self.rows()
        self.assertEqual(volume_proof(rows, ['Q13A','Q13B','Q13C'], 1)[0], 'PASS')
        rows[3]['marker'] = 'verdict:Q13B:0'
        status, detail = volume_proof(rows, ['Q13A','Q13B','Q13C'], 1)
        self.assertEqual(status, 'BLOCKED')
        self.assertIn('verdict:Q13C:0', detail['missing'])
        self.assertIn('verdict:Q13B:0', detail['missing'])

    def test_extra_and_failed_phase_samples_block(self):
        for extra in [dict(marker='verdict:Q13A:1',raw='volume is 7',status='OK'),
                      dict(marker='MARK warming',raw='',status='BLOCKED')]:
            self.assertEqual(volume_proof(self.rows()+[extra], ['Q13A','Q13B','Q13C'], 1)[0], 'BLOCKED')

    def test_source_fail_remains_fail_and_missing_proof_is_explicit(self):
        text='\n'.join(f'VERDICT {v} FAIL could not reach warming state' for v in ['Q13A','Q13B','Q13C'])
        self.assertTrue(all(r['status']=='FAIL' for r in reduce_alias('warmmute',1,text,self.rows())))
        rows=reduce_alias('warmmute',1,text,self.rows()[:-1])
        self.assertTrue(all(r['status']=='BLOCKED' for r in rows))
        self.assertEqual(rows[0]['numbers']['systemVolumeProof']['missing'], ['after'])

    def test_alias_preserves_explicit_blocked_checks_after_host_failure(self):
        import coverage_cp2
        import cp2_alias
        with tempfile.TemporaryDirectory() as directory:
            task=Path(directory)
            args=SimpleNamespace(scene='warmmute',runs=1,run_id='fake',timeout=1)
            with patch.object(coverage_cp2,'TOOL',task), patch.object(coverage_cp2,'ROOT',task), \
                 patch.object(cp2_alias.subprocess,'run',side_effect=TimeoutError('fake transport')):
                cp2_alias.run(args)
            data=json.loads((task/'coverage_evidence/matrix-fake/matrix-fake-cp2-warmmute.json').read_text())
            self.assertEqual(len(data['records']),3)
            self.assertTrue(all(r['status']=='BLOCKED' for r in data['records']))
            self.assertIn('before',data['records'][0]['numbers']['systemVolumeProof']['missing'])
            self.assertIn('TimeoutError',data['harness'][0])

    def test_worker_persists_samples_and_drains_before_close(self):
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'volume.json'
            sampler=VolumeSampler(path, lambda: 'volume is 7')
            sampler.submit('before')
            sampler.submit('after')
            sampler.close()
            self.assertTrue(path.exists())
            self.assertEqual([r['marker'] for r in sampler.rows], ['before','after'])
            self.assertFalse(sampler.worker.is_alive())


if __name__ == '__main__':
    unittest.main()
