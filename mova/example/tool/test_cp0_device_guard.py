"""Transport waits use 30s probe starts and a hard 900s ceiling, without adb."""
import contextlib
import io
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import cp0_device_guard as guard


class TransportTimingTests(unittest.TestCase):
    def run_guard(self, states):
        now = [0.0]
        starts, commands = [], []
        sequence = iter(states)

        def run(argv, **kwargs):
            commands.append(argv)
            if argv[-1] == 'kill-server':
                return subprocess.CompletedProcess(argv, 0, b'', b'')
            starts.append(now[0])
            state = next(sequence, 'timeout')
            if state == 'timeout':
                now[0] += 15
                raise subprocess.TimeoutExpired(argv, 15)
            return subprocess.CompletedProcess(argv, 0, state.encode(), b'')

        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'coverage_evidence').mkdir()
            guard._offline_since = None
            with patch.object(guard, 'Path', return_value=root / 'guard.py'), \
                 patch.object(guard.subprocess, 'run', side_effect=run), \
                 patch.object(guard.time, 'monotonic', side_effect=lambda: now[0]), \
                 patch.object(guard.time, 'sleep', side_effect=lambda seconds: now.__setitem__(0, now[0] + seconds)), \
                 contextlib.redirect_stdout(io.StringIO()):
                try:
                    guard.wait_online('offline-unit')
                    error = None
                except RuntimeError as caught:
                    error = str(caught)
        return starts, commands, now[0], error

    def test_probe_timeout_is_included_in_thirty_second_interval(self):
        starts, _, elapsed, error = self.run_guard(['timeout', 'timeout', 'device'])
        self.assertEqual(starts, [0, 30, 60])
        self.assertEqual(elapsed, 60)
        self.assertIsNone(error)
        self.assertIsNone(guard._offline_since)

    def test_unauthorized_kills_server_before_next_probe(self):
        starts, commands, _, error = self.run_guard(['unauthorized', 'device'])
        self.assertEqual(starts, [0, 30])
        self.assertEqual(commands[1], ['adb', 'kill-server'])
        self.assertIsNone(error)

    def test_timeout_loop_stops_at_fifteen_minutes(self):
        starts, _, elapsed, error = self.run_guard([])
        self.assertEqual(starts, list(range(0, 900, 30)))
        self.assertEqual(elapsed, 900)
        self.assertEqual(error, 'CP0_DEVICE_OFFLINE_15_MINUTES')


if __name__ == '__main__':
    unittest.main()
