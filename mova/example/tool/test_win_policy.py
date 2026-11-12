"""Windows 真机测试策略的离线单测：静态闸门与采样次数钳位；不启动任何窗口。

纯 Python，不连设备。闸门的禁用词在这里用字符串拼接写出，避免本文件被当成违规；
Windows 路径样本用 chr(92) 构造反斜杠，避免任何转义歧义。
"""
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import win_focus_gate as gate
import win_policy

BS = chr(92)
EXE_FWD = 'x/runner/Release/mova_example.exe'
EXE_BACK = BS.join(['x', 'runner', 'Release', 'mova_example.exe'])


def _scan_one(name, text):
    """把 text 写成临时目录里的 name，扫描并返回违规列表。"""
    with tempfile.TemporaryDirectory() as tmp:
        (Path(tmp) / name).write_text(text, encoding='utf-8')
        return gate.scan(tmp)


def _rules(problems):
    """违规列表里的规则名集合。"""
    return {p[2] for p in problems}


class FocusGateTests(unittest.TestCase):
    """闸门要抓到抢焦点、绕过入口、私自放大次数，且不误报构建/审计脚本。"""

    def test_repo_tools_are_clean(self):
        """example/tool 整棵树当前没有任何违规。"""
        problems = gate.scan(gate.TOOL)
        self.assertEqual(problems, [], gate.format_problems(problems))

    def test_foreground_apis_are_rejected(self):
        for api in ('Set' + 'ForegroundWindow', 'BringWindow' + 'ToTop', 'Switch' + 'ToThisWindow',
                    'Attach' + 'ThreadInput', 'Set' + 'ActiveWindow', 'Allow' + 'SetForegroundWindow'):
            self.assertIn('foreground-api', _rules(_scan_one('driver.py', f'user32.{api}(h)\n')), api)

    def test_activating_show_window_is_rejected_but_noactivate_is_allowed(self):
        self.assertIn('show-window-activating', _rules(_scan_one('d.py', 'user32.Show' + 'Window(h, 9)\n')))
        self.assertIn('show-window-activating',
                      _rules(_scan_one('d.py', 'user32.Show' + 'Window(h, SW_' + 'SHOWNORMAL)\n')))
        self.assertEqual(_scan_one('d.py', 'user32.ShowWindow(h, 4)  # SW_SHOWNOACTIVATE\n'), [])
        self.assertEqual(_scan_one('d.py', 'user32.ShowWindow(h, SW_SHOWMINNOACTIVE)\n'), [])

    def test_synthetic_input_and_startfile_are_rejected(self):
        self.assertIn('synthetic-input', _rules(_scan_one('d.py', 'send = keybd' + '_event\n')))
        self.assertIn('os-startfile', _rules(_scan_one('d.py', 'os.start' + "file('x.exe')\n")))
        self.assertIn('start-normal-window',
                      _rules(_scan_one('d.ps1', 'Start-Process app.exe -WindowStyle Normal\n')))

    def test_agents_cannot_raise_the_run_limit_in_scripts(self):
        text = "env['MOVA_WIN_ALLOW_MORE_" + "RUNS']='1'\n"
        self.assertIn('raise-run-limit', _rules(_scan_one('d.py', text)))

    def test_launching_the_app_without_policy_is_rejected(self):
        for exe in (EXE_FWD, EXE_BACK):
            direct = f"import subprocess\nsubprocess.Popen([r'{exe}'])\n"
            self.assertIn('bypass-launcher', _rules(_scan_one('d.py', direct)), exe)
        via_var = f"import subprocess\nEXE = r'{EXE_BACK}'\nsubprocess.Popen([str(EXE)], cwd='.')\n"
        self.assertIn('bypass-launcher', _rules(_scan_one('d.py', via_var)))
        derived = f"import subprocess\nEXE = r'{EXE_FWD}'\nAPP = EXE\nsubprocess.run([APP])\n"
        self.assertIn('bypass-launcher', _rules(_scan_one('d.py', derived)))
        ps = f'Start-Process "{EXE_BACK}"\n'
        self.assertIn('bypass-launcher', _rules(_scan_one('d.ps1', ps)))

    def test_launching_through_policy_is_accepted(self):
        ok = f"import win_policy\nEXE = r'{EXE_FWD}'\napp = win_policy.launch(EXE, '.')\n"
        self.assertEqual(_scan_one('d.py', ok), [])

    def test_build_and_audit_scripts_are_not_false_positives(self):
        build = (f"import subprocess\nEXE = r'{EXE_FWD}'\ndata = open(EXE, 'rb').read()\n"
                 "subprocess.run(['flutter', 'build', 'windows'])\n")
        self.assertEqual(_scan_one('b.py', build), [])
        audit = ("import subprocess\nsubprocess.run(['powershell', '-Command', "
                 "'Get-Process mova_example | Stop-Process'])\n")
        self.assertEqual(_scan_one('a.py', audit), [])


class RunLimitTests(unittest.TestCase):
    """采样次数钳位：默认最多 3 次，只有用户 shell 里的环境变量能放开。"""

    def test_clamps_to_three_by_default(self):
        with patch.dict(os.environ, {}, clear=False):
            os.environ.pop(win_policy.ENV_ALLOW_MORE, None)
            self.assertEqual(win_policy.clamp_runs(20), 3)
            self.assertEqual(win_policy.clamp_runs(30), 3)
            self.assertEqual(win_policy.clamp_runs(2), 2)
            self.assertEqual(win_policy.clamp_runs(3), 3)

    def test_user_env_can_raise_the_limit(self):
        with patch.dict(os.environ, {win_policy.ENV_ALLOW_MORE: '1'}):
            self.assertEqual(win_policy.clamp_runs(20), 20)

    def test_launch_strips_interactive_env_var(self):
        """launch 会去掉 MOVA_WIN_INTERACTIVE，测试进程永远不是交互模式。"""
        captured = {}

        def fake_window(exe, cwd, env, stdout):
            captured.update(env)
            return object()

        with patch.object(win_policy, '_launch_window', fake_window):
            win_policy.launch('x.exe', '.', {'MOVA_WIN_INTERACTIVE': '1', 'A': 'b'})
        self.assertNotIn('MOVA_WIN_INTERACTIVE', captured)
        self.assertEqual(captured['A'], 'b')


if __name__ == '__main__':
    unittest.main()
