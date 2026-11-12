"""静态闸门：Windows 测试脚本不得抢焦点、不得绕过统一启动入口、不得私自放大采样次数。

由 `run_matrix.py --check` 与单测调用；违规直接失败。规则来源见 win_policy.py 文档。
被扫描：example/tool 下的 .py/.ps1/.psm1/.bat/.cmd（跳过 coverage_evidence 等产物目录）。
豁免：win_policy.py / win_focus_gate.py 自身（它们要写出禁用词），以及以 test_ 开头的单测。
"""
import ast
import re
import sys
from pathlib import Path

TOOL = Path(__file__).resolve().parent

SCAN_SUFFIXES = {'.py', '.ps1', '.psm1', '.bat', '.cmd'}
SKIP_DIRS = {'coverage_evidence', '__pycache__', 'build', '.dart_tool', 'node_modules', '.git'}
EXEMPT_FILES = {'win_policy.py', 'win_focus_gate.py'}

# (规则名, 正则, 说明)。注释行也会被扫描——被注释掉的抢焦点代码同样不该留着。
FORBIDDEN = [
    ('foreground-api', re.compile(r'\b(SetForegroundWindow|BringWindowToTop|SwitchToThisWindow|'
                                  r'AllowSetForegroundWindow|SetActiveWindow|AttachThreadInput)\b'),
     '激活/置前窗口的 Win32 API'),
    ('synthetic-input', re.compile(r'\b(keybd_event|SendInput|mouse_event|AppActivate)\b'),
     '用合成输入或 AppActivate 抢焦点'),
    ('show-window-activating', re.compile(r'ShowWindow\s*\(\s*[^,()]+,\s*(1|3|5|9|SW_SHOW|SW_SHOWNORMAL|'
                                          r'SW_RESTORE|SW_MAXIMIZE|SW_SHOWMAXIMIZED)\b'),
     '会激活窗口的 ShowWindow 命令（只允许 SW_SHOWNOACTIVATE/SW_SHOWMINNOACTIVE/SW_HIDE 等）'),
    ('start-normal-window', re.compile(r'Start-Process[^\n]*-WindowStyle\s+(Normal|Maximized)', re.I),
     'Start-Process 以普通/最大化窗口启动'),
    ('os-startfile', re.compile(r'\bos\.startfile\s*\('), 'os.startfile 会经 Shell 激活窗口'),
    ('raise-run-limit', re.compile(r'MOVA_WIN_ALLOW_MORE_RUNS'),
     '放大 Windows 采样次数只能由用户在自己的 shell 里设置，脚本不得写它'),
]

EXE_REF = re.compile(r'mova_example\.exe|runner[\\/]+(Release|Debug|Profile)', re.I)
USES_POLICY = re.compile(r'^\s*(import\s+win_policy|from\s+win_policy\s+import)', re.M)
# 非 Python 脚本里"执行 exe"的写法（行内同时出现 exe 引用才算）
SHELL_LAUNCH = re.compile(r'Start-Process|Invoke-Item|Invoke-Expression|(^|\s)&\s|(^|\s)start\s', re.I)
PROCESS_CALLS = {'Popen', 'run', 'call', 'check_call', 'check_output', 'system', 'startfile', 'spawnl', 'spawnv'}


def _launches_exe_py(tree, text):
    """AST 污点分析：subprocess/os 的调用参数里出现 exe 路径（或由它赋值的变量）才算"启动应用"。

    只读/哈希/存在性检查（如 EXE.read_bytes()）不在这些调用里，不会误报；构建脚本调用 flutter build 也不会。
    """
    tainted = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Assign):
            segment = ast.get_source_segment(text, node.value) or ''
            if EXE_REF.search(segment):
                for target in node.targets:
                    if isinstance(target, ast.Name):
                        tainted.add(target.id)
    # 污点传播一层：由已污染变量派生的赋值也算（如 APP = EXE.parent / 'x'）
    for node in ast.walk(tree):
        if isinstance(node, ast.Assign):
            names = {n.id for n in ast.walk(node.value) if isinstance(n, ast.Name)}
            if names & tainted:
                for target in node.targets:
                    if isinstance(target, ast.Name):
                        tainted.add(target.id)
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        func = node.func
        name = func.attr if isinstance(func, ast.Attribute) else getattr(func, 'id', '')
        if name not in PROCESS_CALLS:
            continue
        owner = ast.get_source_segment(text, func) or ''
        if not re.match(r'(subprocess|os)\.', owner) and name != 'Popen':
            continue
        # 只看"被执行的程序本身"（argv[0]）：powershell -Command '...mova_example.exe...' 里的进程名不算启动
        first = node.args[0] if node.args else next((k.value for k in node.keywords if k.arg == 'args'), None)
        if first is None:
            continue
        argv0 = first.elts[0] if isinstance(first, (ast.List, ast.Tuple)) and first.elts else first
        argv0_text = ast.get_source_segment(text, argv0) or ''
        if EXE_REF.search(argv0_text):
            return True
        if {n.id for n in ast.walk(argv0) if isinstance(n, ast.Name)} & tainted:
            return True
    return False


def _iter_files(root):
    """遍历 root 下需要扫描的脚本文件。"""
    for path in sorted(Path(root).rglob('*')):
        if not path.is_file() or path.suffix.lower() not in SCAN_SUFFIXES:
            continue
        if any(part in SKIP_DIRS for part in path.relative_to(root).parts):
            continue
        if path.name in EXEMPT_FILES or path.name.startswith('test_'):
            continue
        yield path


def scan(root=TOOL):
    """扫描 root，返回违规列表 [(相对路径, 行号, 规则名, 说明, 命中行)]。空列表表示通过。"""
    root = Path(root)
    problems = []
    for path in _iter_files(root):
        text = path.read_text(encoding='utf-8', errors='replace')
        rel = str(path.relative_to(root)).replace('\\', '/')
        lines = text.splitlines()
        for number, line in enumerate(lines, 1):
            for name, pattern, why in FORBIDDEN:
                if pattern.search(line):
                    problems.append((rel, number, name, why, line.strip()[:160]))
        # 启动测试应用必须经 win_policy 统一入口
        if not USES_POLICY.search(text):
            launches = False
            if path.suffix.lower() == '.py':
                try:
                    launches = _launches_exe_py(ast.parse(text), text)
                except SyntaxError:
                    launches = bool(EXE_REF.search(text))  # 解析不了就保守地按文本判
            else:
                launches = any(EXE_REF.search(l) and SHELL_LAUNCH.search(l) for l in lines)
            if launches:
                problems.append((rel, 0, 'bypass-launcher',
                                 '启动 mova_example.exe 必须经 win_policy.launch()（import win_policy）', ''))
    return problems


def format_problems(problems):
    """把违规列表格式化成多行文本。"""
    return '\n'.join(f'  {rel}:{line} [{name}] {why}  {hit}' for rel, line, name, why, hit in problems)


def main(argv=None):
    """命令行入口：违规返回 1。"""
    root = Path(argv[0]) if argv else TOOL
    problems = scan(root)
    if problems:
        print('WIN FOCUS GATE FAIL: 发现抢焦点/绕过统一入口的写法')
        print(format_problems(problems))
        return 1
    print('WIN FOCUS GATE PASS')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
