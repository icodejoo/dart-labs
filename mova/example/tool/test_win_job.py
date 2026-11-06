"""win_job 单测：作业关闭后，即使"父进程已先死"的孙进程也被杀掉（taskkill /T 做不到的场景）。"""
import os
import subprocess
import sys
import time
import unittest

import win_job

PY = sys.executable


def _alive(pid):
    """进程是否还在。"""
    out = subprocess.run(['tasklist', '/FI', f'PID eq {pid}', '/NH'], capture_output=True, text=True).stdout
    return str(pid) in out


@unittest.skipUnless(os.name == 'nt', '仅 Windows')
class KillOnCloseJobTests(unittest.TestCase):
    def test_orphaned_grandchild_is_killed_when_job_closes(self):
        """爷进程起孙进程后立即退出（孙成孤儿），关闭作业仍应杀掉孙进程。"""
        grandchild_code = 'import time; time.sleep(120)'
        parent_code = (
            'import subprocess, sys\n'
            f"g = subprocess.Popen([sys.executable, '-c', {grandchild_code!r}])\n"
            'print(g.pid, flush=True)\n'
        )
        job = win_job.KillOnCloseJob()
        parent = subprocess.Popen([PY, '-c', parent_code], stdout=subprocess.PIPE, text=True,
                                  creationflags=subprocess.CREATE_NO_WINDOW)
        self.assertTrue(job.assign(parent.pid))
        grandchild_pid = int(parent.stdout.readline())
        parent.wait(timeout=20)  # 父进程已退出，孙进程成孤儿
        self.assertTrue(_alive(grandchild_pid), '孙进程应仍存活')
        job.close()
        for _ in range(50):
            if not _alive(grandchild_pid):
                break
            time.sleep(0.1)
        self.assertFalse(_alive(grandchild_pid), '作业关闭后孤儿孙进程应被杀')

    def test_assign_never_raises_on_bad_pid(self):
        """作业防护是尽力而为：非法 pid（如测试替身的 Mock）只返回 False，不能中断跑批。"""
        with win_job.KillOnCloseJob() as job:
            self.assertFalse(job.assign(object()))
            self.assertFalse(job.assign(-1))

    def test_close_is_idempotent_and_context_manager_works(self):
        with win_job.KillOnCloseJob() as job:
            job.close()
        job.close()


if __name__ == '__main__':
    unittest.main()
