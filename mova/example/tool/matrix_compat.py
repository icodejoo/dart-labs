"""Run historical drivers in an isolated evidence namespace.

隔离旧驱动的证据与文档写入，不复制旧终审结论。
"""
import ast
import builtins
import importlib.machinery
import json
import os
from pathlib import Path
import re
import runpy
import shutil
import subprocess
import sys
import time
from datetime import datetime

HERE = Path(__file__).resolve().parent


def transform(source, filename, evidence, prefix):
    """Redirect path constants while preserving original batch logic.

    只重定向路径常量，保留批次内部判定。
    """
    tree = ast.parse(source, filename)

    class Paths(ast.NodeTransformer):
        """Rewrite tool-owned output paths / 重定向工具输出。"""
        def visit_Constant(self, node):
            """Map exact path constants / 映射完整路径常量。"""
            value = node.value
            if isinstance(value, str):
                if value in ('coverage_evidence', 'example/tool/coverage_evidence'):
                    node.value = str(evidence)
                elif value == 'tool/coverage_isolated_build.log':
                    node.value = str(evidence / (prefix + 'build.driver.log'))
                elif value in ('coverage_media','coverage_tls'):
                    node.value = str(evidence / (prefix + value))
                elif value == 'coverage_media/ca.pem':
                    node.value = str(evidence / (prefix + 'coverage_media') / 'ca.pem')
                elif re.fullmatch(r'doc/plans/[^/]+\.md', value):
                    node.value = str(evidence / (prefix + 'checkpoints.md'))
                elif value == '7NQBB23606003715':
                    node.value = os.environ.get('MOVA_MATRIX_SERIAL', value)
                elif value == 'C:/Program Files/Git/mingw64/bin/openssl.exe':
                    node.value = os.environ.get('MOVA_MATRIX_OPENSSL', shutil.which('openssl') or value)
            return node
    return ast.fix_missing_locations(Paths().visit(tree))


def install(evidence, prefix, case):
    """Instrument all descendant Python/adb calls and legacy output paths.

    给后代 Python/adb 命令加日志，并隔离旧脚本输出。
    """
    evidence = Path(evidence).resolve()
    original_compile = builtins.compile
    original_get_code = importlib.machinery.SourceFileLoader.get_code
    original_join = Path.__truediv__
    original_glob = Path.glob

    def join(path, key):
        """Prefix legacy artifact names / 为旧证据名加运行前缀。"""
        if path == evidence and isinstance(key, str) and not key.startswith(prefix):
            key = prefix + key
        return original_join(path, key)

    def glob(path, pattern, **kwargs):
        """Keep legacy globs inside this run / 限定旧 glob 的运行范围。"""
        if path == evidence and not pattern.startswith(prefix):
            pattern = prefix + pattern
        return original_glob(path, pattern, **kwargs)

    def compile_source(source, filename, mode, *args, **kwargs):
        """Transform exec-loaded batches too / 同时处理 exec 加载的批次。"""
        if (isinstance(source, (str, bytes)) and str(filename).endswith('.py')
                and Path(filename).is_relative_to(HERE)
                and not Path(filename).name.startswith(('run_matrix', 'matrix_'))):
            # ast.parse calls compile itself: temporarily restore it.
            builtins.compile = original_compile
            try:
                source = transform(source, str(filename), evidence, prefix)
            finally:
                builtins.compile = compile_source
        return original_compile(source, filename, mode, *args, **kwargs)

    def get_code(loader, fullname):
        """Bypass historical pyc caches / 绕过旧 pyc 缓存。"""
        if Path(loader.path).is_relative_to(HERE):
            return compile_source(Path(loader.path).read_bytes(), loader.path, 'exec')
        return original_get_code(loader, fullname)

    Path.__truediv__ = join
    Path.glob = glob
    builtins.compile = compile_source
    importlib.machinery.SourceFileLoader.get_code = get_code
    original_popen = subprocess.Popen
    logpath = evidence / (prefix + case + '.commands.driver.log')

    def log(kind, message):
        """Write L-format host command logs / 写 L 格式宿主命令日志。"""
        with logpath.open('a', encoding='utf-8') as stream:
            stream.write(f'[MOVA-COV] {datetime.now().astimezone().isoformat(timespec="milliseconds")} '
                         f'<run={prefix}> <case={case}> {kind} {message}\n')

    class Popen(original_popen):
        """Audit direct and nested commands / 审计直接及嵌套命令。"""
        def __init__(self, args, *pos, **kwargs):
            """Rewrite child Python entrypoints / 重定向子 Python 入口。"""
            args = list(map(str, args))
            self.original_args = args.copy()
            if Path(args[0]).name.lower() in ('adb', 'adb.exe'):
                if '-s' in args:
                    args[args.index('-s') + 1] = os.environ['MOVA_MATRIX_SERIAL']
                else:
                    args[1:1] = ['-s', os.environ['MOVA_MATRIX_SERIAL']]
            if Path(args[0]).name.lower() in ('python', 'python.exe', Path(sys.executable).name.lower()):
                index = next((i for i, v in enumerate(args[1:], 1) if v.endswith('.py')), None)
                if index is not None and Path(args[index]).resolve().is_relative_to(HERE):
                    args = [sys.executable, str(HERE / 'matrix_compat.py'), str(evidence), prefix, case,
                            *args[index:]]
            self.started = time.monotonic()
            self.reported = False
            self.matrix_args = args
            log('CALL', json.dumps(args, ensure_ascii=False))
            kwargs.setdefault('creationflags', subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0)
            try:
                super().__init__(args, *pos, **kwargs)
            except Exception as error:
                log('ERROR', f'kind=HARNESS {error!r}')
                raise

        def _report(self):
            """Record one terminal result / 记录一次终态。"""
            if self.returncode is not None and not self.reported:
                self.reported = True
                log('RET', json.dumps({'argv': self.matrix_args, 'exit': self.returncode,
                                      'seconds': time.monotonic() - self.started}, ensure_ascii=False))
                reason = ''
                if '--name' in self.original_args:
                    name=self.original_args[self.original_args.index('--name')+1]
                    if any(Path(v).name=='coverage_suite_device.py' for v in self.original_args):
                        metadata=evidence/(name+'.run.json')
                        try:
                            if not json.loads(metadata.read_text(encoding='utf-8')).get('completed'):
                                reason='suite completed=false'
                        except (OSError,ValueError):
                            reason='suite completion metadata missing/invalid'
                    elif any(Path(v).name=='coverage_device.py' for v in self.original_args):
                        metadata=evidence/(name+'.json')
                        try:
                            if json.loads(metadata.read_text(encoding='utf-8')).get('status')!='done':
                                reason='API command status is not done'
                        except (OSError,ValueError):
                            reason='API command JSON missing/invalid'
                # An adb probe (e.g. pidof before launch) may legitimately return 1.
                # Only failed child Python drivers imply a swallowed harness error.
                if reason or (self.returncode and Path(self.matrix_args[0]).name.lower() in ('python','python.exe',Path(sys.executable).name.lower())):
                    log('ERROR',f'kind=HARNESS {reason or "child driver nonzero exit"}')
                    with (evidence / (prefix + case + '.harness-errors.jsonl')).open('a', encoding='utf-8') as f:
                        f.write(json.dumps({'argv': self.matrix_args, 'exit': self.returncode,'error':reason}) + '\n')

        def wait(self, *args, **kwargs):
            """Audit wait completion / 审计等待完成。"""
            result = super().wait(*args, **kwargs)
            self._report()
            return result

        def poll(self):
            """Audit polled completion / 审计轮询完成。"""
            result = super().poll()
            self._report()
            return result

    subprocess.Popen = Popen
    sys.dont_write_bytecode = True


def main():
    """Execute one existing tool / 执行一个已有工具。"""
    evidence, prefix, case, target, *args = sys.argv[1:]
    install(evidence, prefix, case)
    sys.argv = [target, *args]
    runpy.run_path(target, run_name='__main__')


if __name__ == '__main__':
    main()
