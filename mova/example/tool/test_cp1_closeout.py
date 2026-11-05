"""Protocol fixtures and adjacent-frame privacy regressions; no device."""
import http.server
from pathlib import Path
import tempfile
import threading
import subprocess
import unittest
from unittest.mock import patch
import urllib.request
import urllib.error

from cp1_sources import Fixtures
from shot_guard import guarded_frame_pair
from cp1_capture import capture_phase, is_capture_marker
from cp1_closeout_batch import completion_identity
from run_matrix import gap_result_kind


class FixtureTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        (self.root/'720').mkdir()
        (self.root/'720/index.m3u8').write_text('#EXTM3U\n#EXTINF:2,\nindex20.ts\n')
        (self.root/'720/index20.ts').write_bytes(b'segment')
        self.fixture = Fixtures(self.root)
        self.server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), self.fixture.handler())
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        self.origin = f'http://127.0.0.1:{self.server.server_port}'

    def tearDown(self):
        self.fixture.gate.set()
        self.server.shutdown()
        self.server.server_close()
        self.tmp.cleanup()

    def get(self, path):
        with urllib.request.urlopen(self.origin+path, timeout=2) as response:
            return response.read().decode()

    def test_live_manifest_stays_absolute_after_six_reopens(self):
        for i in range(6):
            body = self.get(f'/live.m3u8?t={i}')
            self.assertIn(self.origin+'/720/index20.ts', body)
        self.assertEqual(len(self.fixture.stats()['manifests']), 6)

    def test_root_relative_control_resolves_to_an_existing_http_segment(self):
        self.fixture.uri_style = 'root-relative'
        for i in range(6):
            self.assertIn('\n/720/index20.ts\n', self.get(f'/live.m3u8?t={i}'))
            asset = self.fixture.stats()['manifests'][-1]['assets'][0]
            self.assertTrue(asset['exists'])
            self.assertEqual(asset['resolved'], self.origin+'/720/index20.ts')
            self.assertEqual(self.get('/720/index20.ts'), 'segment')

    def test_primary_and_alias_playlists_preserve_full_protocol_and_prefix(self):
        self.assertIn(self.origin+'/primary/720/index.m3u8', self.get('/primary.m3u8'))
        self.assertIn(self.origin+'/primary/720/index20.ts', self.get('/primary/720/index.m3u8'))
        self.assertIn(self.origin+'/720/index20.ts', self.get('/new.m3u8'))
        self.assertIn(self.origin+'/720/index20.ts', self.get('/720/index.m3u8'))

    def test_primary_failure_is_recorded_as_real_http_404(self):
        self.assertEqual(self.get('/primary/720/index20.ts'), 'segment')
        self.fixture.fail_primary = True
        with self.assertRaises(urllib.error.HTTPError) as raised:
            self.get('/primary/720/index20.ts')
        self.assertEqual(raised.exception.code, 404)
        self.assertEqual(self.fixture.stats()['responses'][-1]['status'], 404)
        self.assertEqual(self.get('/720/index20.ts'), 'segment')


class FramePairTests(unittest.TestCase):
    def test_native_and_outer_run_namespaces_are_both_preserved(self):
        record = dict(run_id='native', group='skin', completed=True, harness=[], verdicts=[])
        with self.assertRaises(ValueError):
            gap_result_kind(record, 'native-host', 'skin', 0)
        record.update(completion_identity('native'))
        self.assertEqual(record['nativeRunId'], 'native')
        self.assertEqual(gap_result_kind(record, 'native-host', 'skin', 0), 'OK')

    def test_one_transport_timeout_retries_only_inside_the_same_held_phase(self):
        def fetch(path):
            return {'token': 'held', 'acknowledged': path == '/ack?token=held'}
        with patch('cp1_capture.guarded_frame_pair', side_effect=[
                subprocess.TimeoutExpired('adb screencap', 8), {'captured': True}]):
            result = capture_phase(None, 'test', [], 'held', fetch)
        self.assertTrue(result['captured'])
        self.assertEqual(len(result['attempts']), 2)
        self.assertFalse(result['attempts'][0]['captured'])

    def test_ack_echo_of_marker_is_not_a_second_capture(self):
        self.assertTrue(is_capture_marker('flutter : S7 SHOT 1 shotToken=123'))
        self.assertFalse(is_capture_marker('flutter : SHOT_ACK token=123 marker=S7 SHOT 1'))

    def test_expired_phase_never_captures(self):
        calls = []
        def fetch(path):
            calls.append(path)
            return {'token': 'new'}
        with patch('cp1_capture.guarded_frame_pair') as capture:
            result = capture_phase(None, 'test', [], 'old', fetch)
        self.assertFalse(result['captured'])
        capture.assert_not_called()
        self.assertEqual(calls, ['/'])

    def test_phase_change_during_capture_is_rejected_without_ack(self):
        calls = []
        def fetch(path):
            calls.append(path)
            return {'token': 'old' if len(calls) == 1 else 'new'}
        with patch('cp1_capture.guarded_frame_pair', return_value={'captured': True}):
            result = capture_phase(None, 'test', [], 'old', fetch)
        self.assertFalse(result['phaseConfirmed'])
        self.assertFalse(result['captured'])
        self.assertEqual(calls, ['/', '/'])

    def test_only_same_phase_and_exact_ack_accept_the_pair(self):
        calls = []
        def fetch(path):
            calls.append(path)
            return {'token': 'held', 'acknowledged': path == '/ack?token=held'}
        with patch('cp1_capture.guarded_frame_pair', return_value={'captured': True}):
            result = capture_phase(None, 'test', [], 'held', fetch)
        self.assertTrue(result['captured'])
        self.assertEqual(calls, ['/', '/', '/ack?token=held'])

    def test_foreground_change_discards_both_frames(self):
        with tempfile.TemporaryDirectory() as directory:
            paths = [Path(directory)/f'{i}.png' for i in (1, 2)]
            with patch('shot_guard.read_foreground', side_effect=[(True, ''), (False, 'foreign')]):
                result = guarded_frame_pair(lambda *a, **k: b'png', 'test', paths, gap_seconds=0)
            self.assertFalse(result['captured'])
            self.assertFalse(any(p.exists() for p in paths))

    def test_frame_pair_records_separate_capture_times(self):
        with tempfile.TemporaryDirectory() as directory:
            paths = [Path(directory)/f'{i}.png' for i in (1, 2)]
            with patch('shot_guard.read_foreground', return_value=(True, '')):
                result = guarded_frame_pair(lambda *a, **k: b'png', 'test', paths, gap_seconds=0)
            self.assertTrue(result['captured'])
            self.assertLessEqual(result['frames'][0]['endNs'], result['frames'][1]['startNs'])
            self.assertTrue(all(p.read_bytes() == b'png' for p in paths))


if __name__ == '__main__':
    unittest.main()
