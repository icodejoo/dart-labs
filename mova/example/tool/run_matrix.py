"""One-command Android coverage driver; offline modes never access the device.

Android 覆盖回归入口；list/check/dry-run 完全离线。
"""
import argparse
import ast
from collections import Counter
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import socket
import subprocess
import sys
import time

TOOL = Path(__file__).resolve().parent
ROOT = TOOL.parents[1]
MANIFEST = TOOL / 'matrix_manifest.json'
BASELINE = TOOL / 'coverage_evidence/rerun-final-ledger.json'
PACKAGE = 'com.icodejoo.mova.mova_example.coverage'
STATUSES = {'PASS', 'FAIL', 'BLOCKED'}


def matrix_ids(text):
    """Read v1 IDs including the inline event list / 读取表格及行内事件编号。"""
    ids = re.findall(r'^\| ((?:[ACUFN]\d+|E[12])) \|', text, re.M)
    section = text.split('## E.', 1)[1].split('## U.', 1)[0]
    ids += ['E.' + name for name in re.findall(r'`(Mova\w+)`', section) if name != 'MovaEvent']
    ids += [i for i in re.findall(r'\*\*(E[12])\*\*', section) if i not in ids]
    return ids


def expand(argv, run_id, tool=TOOL):
    """Expand argv without invoking a shell / 展开参数，不经过 shell。"""
    return [v.format(python=sys.executable, tool=tool.as_posix(), root=ROOT.as_posix(),
                     evidence=(tool/'coverage_evidence'/f'matrix-{run_id}').as_posix(),
                     run_id=run_id, prefix=f'matrix-{run_id}-') for v in argv]


def extended_matrix_ids(text):
    """Read §10's stable IDs, plus explicit hypotheses from §4 (not ranges)."""
    index = text.split('## 10.', 1)[1]
    ids = set(re.findall(r'^\| (?:v2:|new:)?([A-Z][\w.]*) \|', index, re.M))
    ids.update(re.findall(r'\bH(?:[1-9]|[1-7]\d|78)\b', text))
    return ids


def validate_manifest(manifest, root=ROOT):
    """Validate coverage, dependencies, paths and Python syntax offline.

    离线检查编号、依赖、脚本路径和语法。
    """
    errors = []
    ids = manifest.get('ids', [])
    extended = set()
    try:
        canonical = matrix_ids((root / manifest['matrix']).read_text(encoding='utf-8'))
        extended = extended_matrix_ids((root / manifest['matrix']).read_text(encoding='utf-8'))
        if len(canonical) != 135 or set(ids) != set(canonical):
            errors.append('矩阵编号与清单不一致，必须恰好 135 个')
    except (OSError, KeyError, IndexError) as error:
        errors.append(f'矩阵无法解析: {error}')
    if len(ids) != 135 or len(set(ids)) != 135:
        errors.append('ids 必须为 135 个不重复编号')
    covered = set()
    seen = {'services', 'build'}
    tool = root / 'example/tool'
    for batch in manifest.get('batches', []):
        ident = batch.get('id')
        if not ident or ident in seen:
            errors.append(f'重复/空批次: {ident}')
        if not set(batch.get('dependencies', [])) <= seen:
            errors.append(f'{ident}: 依赖不存在或顺序错误')
        seen.add(ident)
        covered.update(batch.get('covers', []))
        extra = batch.get('covers_ext', [])
        if not isinstance(extra, list) or not all(isinstance(i, str) for i in extra):
            errors.append(f'{ident}: covers_ext 必须为编号数组')
        elif set(extra) - extended:
            errors.append(f'{ident}: 未知扩展编号={sorted(set(extra)-extended)}')
        if batch.get('native_driver'):
            try:
                path=Path(expand([batch['result_path']], 'check', tool)[0])
                if not path.is_relative_to(tool) or path.suffix!='.json':
                    raise ValueError('result_path 必须在 tool 内并以 .json 结尾')
                if not isinstance(batch.get('argv'),list) or batch['argv'][1]!='{tool}/coverage_gap.py':
                    raise ValueError('native_driver 仅用于独立 gap 驱动')
            except (KeyError,ValueError,IndexError) as e:
                errors.append(f'{ident}: 非法 native_driver 元数据: {e}')
        for key in ('description', 'why', 'evidence_prefix', 'screen_on', 'fast'):
            if key not in batch:
                errors.append(f'{ident}: 缺少 {key}')
        if not isinstance(batch.get('timeout'), (int, float)) or batch['timeout'] <= 0:
            errors.append(f'{ident}: 非法 timeout')
    manuals = manifest.get('manual', [])
    if len({row['id'] for row in manuals}) != len(manuals):
        errors.append('manual 编号重复')
    for row in manuals:
        covered.add(row['id'])
        if not row.get('reason'):
            errors.append(f"{row['id']}: manual 缺少原因")
    if covered != set(ids):
        errors.append(f'覆盖缺失={sorted(set(ids)-covered)} 未知={sorted(covered-set(ids))}')
    build=manifest.get('build',{})
    jobs=manifest.get('batches', []) + manifest.get('services', [])
    if build:
        jobs += [dict(id='build',argv=build.get('argv')),dict(id='repack',argv=build.get('repack_argv'))]
    for job in jobs:
        argv = job.get('argv')
        if not isinstance(argv, list) or not argv or not all(isinstance(v, str) and v for v in argv):
            errors.append(f"{job['id']}: argv 必须为非空字符串数组")
            continue
        try:
            command = expand(argv, 'check', tool)
            if command[0] != sys.executable or len(command) < 2:
                raise ValueError('只支持显式 Python 脚本命令')
            for arg in command[1:]:
                if arg.endswith('.py'):
                    path = Path(arg) if Path(arg).is_absolute() else tool / arg
                    if not path.is_relative_to(tool):
                        raise ValueError(f'脚本越界: {path}')
                    ast.parse(path.read_text(encoding='utf-8-sig'), str(path))
            entry = Path(command[1])
            source = ast.parse(entry.read_text(encoding='utf-8-sig'), str(entry))
            declarations = [n for n in ast.walk(source) if isinstance(n,ast.Call)
                            and isinstance(n.func,ast.Attribute) and n.func.attr=='add_argument']
            flags = {a.value for n in declarations for a in n.args
                     if isinstance(a,ast.Constant) and isinstance(a.value,str) and a.value.startswith('--')}
            if declarations:
                unknown = [v for v in command[2:] if v.startswith('--') and v.split('=')[0] not in flags]
                if unknown:
                    raise ValueError(f'未知脚本参数: {unknown}')
        except (OSError, ValueError, KeyError, SyntaxError) as error:
            errors.append(f"{job['id']}: 命令无法解析: {error}")
    return errors


def select_batches(manifest, only=None, start=None, fast=False):
    """Select ordered jobs and close batch dependencies / 按顺序选择并补齐批次依赖。"""
    batches = manifest['batches']
    known = {b['id'] for b in batches}
    wanted = set(only.split(',')) if only else set(known)
    if wanted - known or (start and start not in known):
        raise ValueError(f'未知批次: {sorted(wanted-known)} {start or ""}')
    if fast:
        wanted &= {b['id'] for b in batches if b['fast']}
    if start:
        wanted &= {b['id'] for b in batches[next(i for i,b in enumerate(batches) if b['id']==start):]}
    # Dependency launch is required even for --from; no old evidence is imported.
    changed = True
    while changed:
        before = wanted.copy()
        for b in batches:
            if b['id'] in wanted:
                wanted.update(set(b['dependencies']) & known)
        changed = before != wanted
    return [b for b in batches if b['id'] in wanted]


def gap_result_kind(result, run_id, group, code):
    """Keep product FAIL/BLOCKED separate from process/harness failure."""
    if result.get('run_id')!=run_id or result.get('group')!=group:
        raise ValueError('gap result identity mismatch')
    if not isinstance(result.get('completed'),bool) or not isinstance(result.get('harness'),list):
        raise ValueError('gap completion schema mismatch')
    if not isinstance(result.get('verdicts'),list) or any(
        not isinstance(v,dict) or v.get('status') not in STATUSES or
        not str(v.get('case','')).startswith('gap:') for v in result['verdicts']):
        raise ValueError('gap verdict schema mismatch')
    if code not in (0,1) or result['harness']:
        return 'HARNESS'
    return 'OK' if result['completed'] else 'BLOCKED'


def read_ledger(data):
    """Normalize existing finalizer ledgers / 兼容已有终审台账格式。"""
    rows = data['rows'] if isinstance(data, dict) else data
    result = {}
    for row in rows:
        item = row if isinstance(row, dict) else dict(zip(('id','status','evidence'), row))
        if item['id'] in result or item['status'] not in STATUSES:
            raise ValueError('重复编号或非法台账结论')
        result[item['id']] = item
    return result


def compare_ledgers(rows, baseline):
    """Compare statuses using rerun_finalize categories / 沿用终审的状态对比口径。"""
    old = read_ledger(baseline)
    result = {k: [] for k in ('新增失败','已修复','仍失败','仍阻塞','新增阻塞','已解除阻塞')}
    for row in rows:
        ident, status = row['id'], row['status']
        previous = old.get(ident, {}).get('status')
        if status == 'FAIL':
            result['仍失败' if previous == 'FAIL' else '新增失败'].append(ident)
        if previous == 'FAIL' and status == 'PASS':
            result['已修复'].append(ident)
        if status == 'BLOCKED':
            result['仍阻塞' if previous == 'BLOCKED' else '新增阻塞'].append(ident)
        if previous == 'BLOCKED' and status == 'PASS':
            result['已解除阻塞'].append(ident)
    return result


def make_rows(manifest, results, explicit):
    """Use only complete current-run verdicts; keep partial checks as evidence.

    只接收本轮完整编号结论；子项检查不冒充整项通过。
    """
    manual = {r['id']: r['reason'] for r in manifest['manual']}
    rows = []
    for ident in manifest['ids']:
        jobs = [b for b in manifest['batches'] if ident in b['covers']]
        names = [b['id'] for b in jobs]
        completed = bool(names) and all(results.get(n, {}).get('kind') == 'OK' for n in names)
        evidence = [results[n]['driver'] for n in names if n in results]
        status, detail = 'BLOCKED', manual.get(ident, '缺少完整编号自动判据；现有子项结果需复核，不能复用旧 finalize 硬编码结论。')
        if ident not in manual and not completed:
            detail = '覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。'
        if ident not in manual and completed and ident in explicit:
            status, detail = explicit[ident]['status'], explicit[ident]['evidence']
        rows.append(dict(id=ident, status=status, evidence=detail, batches=names,
                         reproduction='python example/tool/run_matrix.py --only ' + ','.join(names) if names else 'manual',
                         pointers=evidence))
    return rows


def render_summary(run_id, rows, comparison, results, baseline):
    """Render a standalone reviewable Markdown report / 生成独立可复核汇总。"""
    counts = Counter(r['status'] for r in rows)
    lines = [f'# Android matrix run {run_id}', '', f'基线：`{baseline}`。仅本轮证据入账；BLOCKED 不表示产品 FAIL。', '',
             '| 总数 | PASS | FAIL | BLOCKED |', '|---|---|---|---|',
             f'| {len(rows)} | {counts["PASS"]} | {counts["FAIL"]} | {counts["BLOCKED"]} |', '',
             '| 对比 | 编号 |', '|---|---|']
    lines += [f'| {key} | {", ".join(value) or "无"} |' for key,value in comparison.items()]
    lines += ['', '验证器问题（HARNESS；与产品缺陷分开）：', '']
    lines += [f'- {name}: {r.get("error", r["kind"])}；`{r["driver"]}`' for name,r in results.items() if r['kind'] != 'OK'] or ['- 无。']
    lines += ['', '| 编号 | 结论 | 原因与证据 | 最小复现入口 |', '|---|---|---|---|']
    for row in rows:
        detail = (row['evidence'] + ' ' + ' '.join(row['pointers'])).replace('|','/').replace('\n',' ')
        lines.append(f'| {row["id"]} | {row["status"]} | {detail} | `{row["reproduction"]}` |')
    gap_results = [(name,r['gap_result']) for name,r in results.items() if 'gap_result' in r]
    if gap_results:
        lines += ['', 'Gap 扩展子项（不改变上方 v1 135 编号台账；完整证据见独立 gap.json）：', '',
                  '| 批次 | case | 结论 | 原因 |', '|---|---|---|---|']
        for name,result in gap_results:
            for verdict in result.get('verdicts',[]):
                detail=str(verdict.get('reason') or verdict.get('difference') or '').replace('|','/').replace('\n',' ')
                lines.append(f'| {name} | {verdict["case"]} | {verdict["status"]} | {detail} |')
    lines += ['', '范围：v1 135 编号；gap 扩展按子项独立呈现，不能推定完整编号通过。', '']
    return '\n'.join(lines)


def is_unlocked(window):
    """Require explicit positive native screen markers / 必须有明确原生解锁亮屏标记。"""
    return ('isKeyguardShowing=false' in window and 'isKeyguardShowing=true' not in window
            and 'mScreenOnFully=true' in window)


def existing_verdicts(out, prefix):
    """Reuse unchanged full-ID CHECKs cited by rerun_finalize, in both engines.

    复用终审引用的完整编号 CHECK，必须普通和代理两份均存在。
    """
    verdicts = {}
    for ident in ('A4', 'A22'):
        matches = []
        for suffix in ('rerun-batch15-basic.json','rerun-batch15-basic-cutover.json'):
            path = out / (prefix + suffix)
            if not path.exists():
                break
            data = json.loads(path.read_text(encoding='utf-8'))
            records = data.get('records', [])
            start = max((i for i,r in enumerate(records) if r.get('kind')=='BEGIN'),default=0)
            checks = [r for r in records[start:] if r.get('kind')=='CHECK' and r.get('id')==ident]
            if not checks or any(type(r.get('pass')) is not bool for r in checks):
                break
            matches += [(r,path) for r in checks]
        else:
            verdicts[ident] = dict(status='PASS' if all(r['pass'] for r,p in matches) else 'FAIL',
                                   evidence='复用 rerun_finalize 引用的两实现完整编号 CHECK：' +
                                   '; '.join(f'{p.name}: {r}' for r,p in matches))
    return verdicts


def subcheck_observations(out, since=0):
    """Retain existing raw CHECK failures without inventing full-ID verdicts.

    留存既有 CHECK 子项失败，不将其伪装成完整编号结论。
    """
    failures=[]
    for path in out.glob('*.json'):
        if path.stat().st_mtime < since:
            continue
        try:
            data=json.loads(path.read_text(encoding='utf-8'))
        except (OSError,ValueError):
            continue
        if not isinstance(data,dict) or 'records' not in data:
            continue
        records=data['records']
        start=max((i for i,r in enumerate(records) if r.get('kind')=='BEGIN'),default=0)
        failures += [dict(file=str(path),check=r) for r in records[start:]
                     if r.get('kind')=='CHECK' and r.get('pass') is False]
    for path in out.glob('*.log'):
        if path.name.endswith('.driver.log') or path.stat().st_mtime < since:
            continue
        for line in path.read_text(encoding='utf-8',errors='replace').splitlines():
            if re.search(r'\bVERDICT\s+\S+\s+FAIL\b|\|FAIL\|',line):
                failures.append(dict(file=str(path),check=dict(kind='LOG',line=line)))
    return failures


class Driver:
    """Own processes, installation and restoration / 管理进程、安装与恢复。"""
    def __init__(self, args, manifest):
        """Allocate a fresh evidence namespace / 分配全新证据目录。"""
        self.args, self.manifest = args, manifest
        self.prefix = f'matrix-{args.run_id}-'
        self.out = TOOL / 'coverage_evidence' / f'matrix-{args.run_id}'
        self.out.mkdir(parents=True, exist_ok=False)
        self.serial = os.environ.get('MOVA_MATRIX_SERIAL', os.environ.get('ANDROID_SERIAL', '7NQBB23606003715'))
        self.env = dict(os.environ, MOVA_MATRIX_SERIAL=self.serial, PYTHONDONTWRITEBYTECODE='1')
        self.log = self.out / (self.prefix + 'driver.log')
        self.children, self.saved, self.results = [], {}, {}
        self.mappings = []
        self.original_mappings = {'reverse':{},'forward':{}}

    def note(self, kind, detail, case='driver'):
        """Write one L-format line / 写一行 L 格式日志。"""
        line = f'[MOVA-COV] {datetime.now().astimezone().isoformat(timespec="milliseconds")} <run={self.args.run_id}> <case={case}> {kind} {detail}'
        print(line, flush=True)
        with self.log.open('a', encoding='utf-8') as stream:
            stream.write(line + '\n')

    def command(self, argv, timeout=60, binary=False):
        """Audit every host/adb command, including failures / 审计每条命令及失败。"""
        argv = list(map(str, argv))
        self.note('CALL', json.dumps(argv, ensure_ascii=False))
        start = time.monotonic()
        try:
            p = subprocess.run(argv, cwd=ROOT, env=self.env, capture_output=True, timeout=timeout,
                               creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0)
            self.note('RET', f'exit={p.returncode} seconds={time.monotonic()-start:.3f}')
            if p.returncode:
                raise RuntimeError(f'{argv}: {p.stderr.decode(errors="replace")}')
            return p.stdout if binary else p.stdout.decode('utf-8', errors='replace')
        except Exception as error:
            self.note('ERROR', f'kind=HARNESS seconds={time.monotonic()-start:.3f} {error}')
            raise

    def adb(self, *args, binary=False):
        """Address only the selected device / 只操作指定设备。"""
        return self.command(['adb', '-s', self.serial, *args], binary=binary)

    def screen(self):
        """Stop immediately on lock; never attempt unlock / 锁屏立即停止，不解锁。"""
        window = self.adb('shell','dumpsys','window')
        if not is_unlocked(window):
            raise RuntimeError('设备必须已解锁且亮屏：要求 isKeyguardShowing=false、mScreenOnFully=true；不会尝试解锁。')
        return window

    def preflight(self):
        """Check resources before changing any device setting / 改设备设置前检查资源。"""
        for port in self.manifest['ports']:
            with socket.socket() as sock:
                try:
                    sock.bind(('127.0.0.1', port))
                except OSError as error:
                    raise RuntimeError(f'端口 {port} 被占用；请先结束占用者，不自动杀进程') from error
        if shutil.disk_usage(ROOT).free < 5 * 1024**3:
            raise RuntimeError('宿主磁盘可用空间不足 5 GiB')
        if self.adb('get-state').strip() != 'device':
            raise RuntimeError('设备不在线/未授权')
        window = self.screen()
        (self.out / (self.prefix+'preflight.window.txt')).write_text(window, encoding='utf-8')
        disk = self.adb('shell','df','-k','/data')
        (self.out / (self.prefix+'preflight.disk.txt')).write_text(disk, encoding='utf-8')
        fields = disk.strip().splitlines()[-1].split()
        if len(fields) < 4 or not fields[3].isdigit() or int(fields[3]) < 1024*1024:
            raise RuntimeError('无法确认设备 /data 可用空间 >= 1 GiB')
        power = self.adb('shell','settings','get','global','stay_on_while_plugged_in').strip()
        volume = self.adb('shell','media','volume','--stream','3','--get')
        match = re.search(r'volume is (\d+)', volume, re.I)
        if not match:
            raise RuntimeError('无法读取媒体音量原值，停止以避免无法恢复')
        self.saved = dict(power=power, volume=match[1])
        for direction in self.original_mappings:
            for line in self.adb(direction,'--list').splitlines():
                parts=line.split()
                if len(parts)==3 and (direction=='reverse' or parts[0]==self.serial):
                    self.original_mappings[direction][parts[1]]=parts[2]
        self.saved['mappings']=self.original_mappings
        (self.out / (self.prefix+'restore.json')).write_text(json.dumps(self.saved), encoding='utf-8')
        self.adb('shell','settings','put','global','stay_on_while_plugged_in','7')

    def wrapped(self, argv, case):
        """Launch through the legacy isolation adapter / 通过旧脚本隔离适配器启动。"""
        return [sys.executable, str(TOOL/'matrix_compat.py'), str(self.out), self.prefix, case, *argv[1:]]

    def build(self):
        """Reuse Gradle/repack, sign, install and verify the pulled APK hash.

        复用构建重打包，签名安装后拉包核对哈希与安装时间。
        """
        self.screen()
        before = self.adb('shell','dumpsys','package',PACKAGE)
        path = self.adb('shell','pm','path',PACKAGE).strip().removeprefix('package:')
        installed = self.out / (self.prefix+'installed-before.apk')
        self.adb('pull',path,str(installed))
        self.command(self.wrapped(expand(self.manifest['build']['argv'],self.args.run_id),'build'), self.manifest['build']['timeout'])
        self.command(self.wrapped(expand(self.manifest['build']['repack_argv'],self.args.run_id),'repack'), 300)
        sdk = Path(os.environ.get('ANDROID_SDK_ROOT') or os.environ.get('ANDROID_HOME') or Path.home()/'AppData/Local/Android/Sdk')
        versions = sorted((sdk/'build-tools').glob('*'), key=lambda p: [int(x) if x.isdigit() else 0 for x in re.split(r'[.-]',p.name)])
        if not versions:
            raise RuntimeError('找不到 build-tools；请设置 ANDROID_SDK_ROOT')
        bt = versions[-1]
        aligned, signed = [self.out/(self.prefix+n+'.apk') for n in ('aligned','installed')]
        self.command([bt/'zipalign.exe','-f','-p','4',self.out/(self.prefix+'coverage-unsigned.apk'),aligned])
        self.command([bt/'apksigner.bat','sign','--ks',Path.home()/'.android/debug.keystore','--ks-key-alias','androiddebugkey','--ks-pass','pass:android','--out',signed,aligned])
        self.command([bt/'apksigner.bat','verify','--verbose',signed])
        self.screen()
        self.adb('install','-r',str(signed))
        after = self.adb('shell','dumpsys','package',PACKAGE)
        path = self.adb('shell','pm','path',PACKAGE).strip().removeprefix('package:')
        pulled = self.out/(self.prefix+'device-pulled.apk')
        self.adb('pull',path,str(pulled))
        hashes = {}
        for key,path in [('signed',signed),('device',pulled)]:
            with path.open('rb') as stream:
                hashes[key]=hashlib.file_digest(stream,'sha256').hexdigest()
        previous = re.findall(r'lastUpdateTime=(.+)',before)
        current = re.findall(r'lastUpdateTime=(.+)',after)
        metadata = dict(sha256=hashes, previousLastUpdateTime=previous, lastUpdateTime=current)
        (self.out/(self.prefix+'build.json')).write_text(json.dumps(metadata,indent=2), encoding='utf-8')
        if hashes['signed'] != hashes['device'] or not current or current == previous:
            raise RuntimeError('新包核验失败：拉包 hash 或 lastUpdateTime 不匹配')

    def services(self):
        """Start owned fixtures and wait for all listening ports / 启动自有夹具并等待端口。"""
        sources=self.out/(self.prefix+'sources')
        sources.mkdir()
        shutil.copyfile(TOOL/'coverage_sources/stall.mp4',sources/'stall.mp4')
        for service in self.manifest['services']:
            argv = self.wrapped(expand(service['argv'],self.args.run_id),service['id'])
            stream = (self.out/(self.prefix+service['id']+'.driver.log')).open('w',encoding='utf-8')
            child = subprocess.Popen(argv,cwd=ROOT,env=self.env,stdout=stream,stderr=subprocess.STDOUT,
                                     creationflags=subprocess.CREATE_NO_WINDOW if os.name=='nt' else 0)
            self.children.append((child,stream))
            self.note('CALL',f'pid={child.pid} {argv}')
            end = time.monotonic()+120
            pending = set(service['ports'])
            while pending and child.poll() is None and time.monotonic()<end:
                for port in list(pending):
                    try:
                        with socket.create_connection(('127.0.0.1',port),timeout=.2):
                            pending.remove(port)
                    except OSError:
                        pass
                time.sleep(.2)
            if pending or child.poll() is not None:
                raise RuntimeError(f'服务 {service["id"]} 未就绪: {pending}')
            for port in service['ports']:
                self.adb('reverse',f'tcp:{port}',f'tcp:{port}')
                self.mappings.append(('reverse',port))
        self.adb('forward','tcp:18083','tcp:18083')
        self.mappings.append(('forward',18083))

    def capture_failure(self, case):
        """Best-effort failure snapshot without hiding errors / 尽力留现场且记录取证错误。"""
        for suffix,cmd in [('window.txt',('shell','dumpsys','window')),('audio.txt',('shell','dumpsys','audio')),
                           ('logcat.txt',('logcat','-d','-v','threadtime')),('png',('exec-out','screencap','-p'))]:
            try:
                payload = self.adb(*cmd,binary=True)
                (self.out/(self.prefix+case+'.failure.'+suffix)).write_bytes(payload)
            except Exception as error:
                self.note('ERROR',f'kind=HARNESS 取证失败 {error}',case)
        try:
            import urllib.request
            with urllib.request.urlopen('http://127.0.0.1:18083/',timeout=3) as response:
                data=json.load(response)
            (self.out/(self.prefix+case+'.recent-events.json')).write_text(json.dumps(data.get('records',[])[-50:],ensure_ascii=False,indent=2),encoding='utf-8')
        except Exception as error:
            self.note('ERROR',f'kind=HARNESS 最近事件读取失败 {error}',case)

    def batch(self, job):
        """Run a bounded process tree and preserve harness failures / 有界执行进程树并留存错误。"""
        case = job['id']
        self.screen()
        self.mappings.append(('reverse',18082))
        self.note('BEGIN',f'{job["description"]}；为什么：{job["why"]}',case)
        path = self.out/(self.prefix+case+'.driver.log')
        start=time.monotonic()
        wall_start=time.time()
        error=''
        with path.open('w',encoding='utf-8') as stream:
            command = expand(job['argv'],self.args.run_id)
            # New structured drivers own their namespace and L logging. The
            # historical AST adapter would rewrite their shared fixture paths.
            if not job.get('native_driver', False):
                command = self.wrapped(command,case)
            child=subprocess.Popen(command,cwd=ROOT,env=self.env,
                                   stdout=stream,stderr=subprocess.STDOUT,
                                   creationflags=subprocess.CREATE_NO_WINDOW if os.name=='nt' else 0)
            try:
                code=child.wait(timeout=job['timeout'])
            except (subprocess.TimeoutExpired, KeyboardInterrupt):
                self.kill_tree(child)
                code=-1
                error='验证器超时/中断'
        markers=list(self.out.glob(self.prefix+case+'.harness-errors.jsonl'))
        # Existing suite drivers sometimes exit 0 even when their completion marker is absent.
        runmeta=self.out/(self.prefix+case+'.run.json')
        incomplete=runmeta.exists() and not json.loads(runmeta.read_text(encoding='utf-8')).get('completed')
        kind='HARNESS' if code or markers or incomplete else 'OK'
        gap_result = None
        if job.get('native_driver'):
            try:
                result_path=Path(expand([job['result_path']],self.args.run_id)[0])
                gap_result=json.loads(result_path.read_text(encoding='utf-8'))
                kind=gap_result_kind(gap_result,self.args.run_id,case.removeprefix('gap-'),code)
            except (OSError,ValueError,KeyError) as e:
                kind='HARNESS';error=f'gap completion metadata: {e}'
        self.results[case]=dict(kind=kind,exit=code,seconds=time.monotonic()-start,driver=str(path),error=error or ('子命令失败/缺完成标记' if kind=='HARNESS' else ''))
        if gap_result is not None:
            self.results[case]['gap_result']=gap_result
        observations=subcheck_observations(self.out,wall_start)
        self.results[case]['subcheck_failures']=observations
        self.note('END',f'exit={code} seconds={time.monotonic()-start:.3f} kind={kind}',case)
        if kind!='OK' or observations:
            self.capture_failure(case)
        # Full-ID product verdicts are independent of the verifier exit code.
        product_failure=any(v['status']=='FAIL' for v in existing_verdicts(self.out,self.prefix).values())
        if gap_result is not None:
            product_failure |= any(v.get('status')=='FAIL' for v in gap_result.get('verdicts',[]))
        if product_failure:
            self.note('VERDICT','FAIL 完整编号 CHECK 失败，详见本轮 JSON',case)
            self.capture_failure(case)
        self.screen()
        return kind=='OK' and not product_failure

    def kill_tree(self, child):
        """Terminate only the owned process tree / 仅终止自有进程树。"""
        if child.poll() is None:
            if os.name=='nt':
                self.command(['taskkill','/PID',str(child.pid),'/T','/F'])
            else:
                child.terminate()
            child.wait(timeout=10)

    def cleanup(self):
        """Restore saved settings even after failures / 即使失败也恢复已保存设置。"""
        actions=[]
        if self.saved:
            actions += [('shell','am','force-stop',PACKAGE),('shell','media','volume','--stream','3','--set',self.saved['volume'])]
            actions += [('shell','settings','delete','global','stay_on_while_plugged_in') if self.saved['power']=='null'
                        else ('shell','settings','put','global','stay_on_while_plugged_in',self.saved['power'])]
        for action in actions:
            try:
                self.adb(*action)
            except Exception as error:
                self.results['cleanup']=dict(kind='HARNESS',driver=str(self.log),error=str(error))
        if self.saved:
            try:
                power=self.adb('shell','settings','get','global','stay_on_while_plugged_in').strip()
                volume=self.adb('shell','media','volume','--stream','3','--get')
                (self.out/(self.prefix+'restored.txt')).write_text(power+'\n'+volume,encoding='utf-8')
                match=re.search(r'volume is (\d+)',volume,re.I)
                if power!=self.saved['power'] or not match or match[1]!=self.saved['volume']:
                    raise RuntimeError('恢复后原生读回与起始值不一致')
            except Exception as error:
                self.results['cleanup']=dict(kind='HARNESS',driver=str(self.log),error=str(error))
        for direction,port in set(self.mappings):
            try:
                source=f'tcp:{port}'
                previous=self.original_mappings[direction].get(source)
                if previous:
                    self.adb(direction,source,previous)
                else:
                    self.adb(direction,'--remove',source)
            except Exception as error:
                self.note('ERROR',f'kind=HARNESS 映射清理失败 {error}')
        for child,stream in reversed(self.children):
            try:
                self.kill_tree(child)
                self.note('RET',f'owned service pid={child.pid} exit={child.returncode}')
            except Exception as error:
                self.note('ERROR',f'kind=HARNESS 服务清理失败 {error}')
                self.results['cleanup-services']=dict(kind='HARNESS',driver=str(self.log),error=str(error))
            stream.close()


def main(argv=None):
    """Parse offline modes before constructing any driver / 离线分支先于任何设备操作。"""
    parser=argparse.ArgumentParser(description=__doc__)
    for flag in ('list','check','fast','dry-run','fail-fast'):
        parser.add_argument('--'+flag,action='store_true')
    parser.add_argument('--only')
    parser.add_argument('--from',dest='start')
    parser.add_argument('--run-id',default=datetime.now().strftime('%Y%m%d-%H%M%S'))
    parser.add_argument('--baseline',type=Path,default=BASELINE)
    args=parser.parse_args(argv)
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]{0,79}',args.run_id):
        parser.error('run-id 只允许字母数字、点、下划线和短横线，最多80字符')
    manifest=json.loads(MANIFEST.read_text(encoding='utf-8'))
    errors=validate_manifest(manifest)
    if errors:
        print('\n'.join(errors));return 2
    try:
        selected=select_batches(manifest,args.only,args.start,args.fast)
    except ValueError as error:
        parser.error(str(error))
    if not selected and not args.check and not args.list:
        parser.error('所选条件没有匹配批次')
    if args.check:
        print(f'CHECK PASS: {len(manifest["batches"])} batches / 135 IDs / {len(manifest["manual"])} manual; 无设备操作')
        return 0
    if args.list:
        for job in selected:
            print(f'{job["id"]} fast={job["fast"]} timeout={job["timeout"]} covers={",".join(job["covers"])}' +
                  (f' covers_ext={",".join(job["covers_ext"])}' if job.get('covers_ext') else ''))
        for row in manifest['manual']:
            print(f'manual {row["id"]}: {row["reason"]}')
        return 0
    if args.dry_run:
        print('预检（实际执行时）：端口/磁盘/在线/已解锁亮屏/保存 USB 常亮与媒体音量')
        prefix=f'matrix-{args.run_id}-'
        out=TOOL/'coverage_evidence'/f'matrix-{args.run_id}'
        def preview(cmd,case):
            """Print the actual compatibility wrapper without creating it / 不创建目录，只打印实际包装命令。"""
            return [sys.executable,str(TOOL/'matrix_compat.py'),str(out),prefix,case,*cmd[1:]]
        for cmd in ([sys.executable,str(TOOL/'coverage_build.py'),'lib/main_coverage_suite.dart'],[sys.executable,str(TOOL/'coverage_repack.py')]):
            print(subprocess.list2cmdline(preview(cmd,'build' if 'coverage_build.py' in cmd[1] else 'repack')))
        print('随后 zipalign、apksigner、adb install、拉回 APK sha256 / lastUpdateTime 核验')
        for job in manifest['services']+selected:
            command=expand(job['argv'],args.run_id)
            print(job['id']+': '+subprocess.list2cmdline(command if job.get('native_driver') else preview(command,job['id'])))
        print('finally：force-stop、恢复媒体音量/USB 常亮、移除自有映射、终止自有服务树；生成 MD/JSON')
        return 0
    baseline=json.loads(args.baseline.read_text(encoding='utf-8'))
    read_ledger(baseline)
    driver=Driver(args,manifest)
    checkpoint=driver.out/(driver.prefix+'checkpoints.md')
    checkpoint.write_text('# 本轮自动检查点\n\n| 编号 | 结论 | 本次原因与证据 |\n|---|---|---|\n'+''.join(f'| {i} | BLOCKED | 待本轮证据。 |\n' for i in manifest['ids']),encoding='utf-8')
    try:
        driver.preflight()
        driver.build()
        driver.services()
        for job in selected:
            bad_dependencies=[d for d in job['dependencies'] if d in driver.results and driver.results[d]['kind']!='OK']
            if bad_dependencies:
                driver.results[job['id']]=dict(kind='BLOCKED',driver=str(driver.log),error=f'依赖失败 {bad_dependencies}')
                continue
            if not driver.batch(job) and args.fail_fast:
                break
    except (Exception,KeyboardInterrupt) as error:
        driver.note('ERROR',f'kind=HARNESS {error}')
        driver.results['driver']=dict(kind='HARNESS',driver=str(driver.log),error=str(error))
    finally:
        driver.cleanup()
        explicit={i:dict(status=s,evidence=d) for i,s,d in re.findall(r'^\| (\S+) \| (PASS|FAIL) \| (.*?) \|$',checkpoint.read_text(encoding='utf-8'),re.M)}
        explicit.update(existing_verdicts(driver.out,driver.prefix))
        rows=make_rows(manifest,driver.results,explicit)
        for row in rows:
            driver.note('EXPECT','完整本轮编号判据通过；缺判据或验证器错误则 BLOCKED',row['id'])
            driver.note('ACTUAL',row['evidence'],row['id'])
            driver.note('VERDICT',row['status'],row['id'])
        comparison=compare_ledgers(rows,baseline)
        target=ROOT/'doc/plans'/f'{datetime.now():%Y-%m-%d}-matrix-run-{args.run_id}'
        data=dict(run_id=args.run_id,rows=rows,counts=dict(Counter(r['status'] for r in rows)),comparison=comparison,batches=driver.results,baseline=str(args.baseline),evidence=str(driver.out))
        Path(str(target)+'.json').write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding='utf-8')
        Path(str(target)+'.md').write_text(render_summary(args.run_id,rows,comparison,driver.results,args.baseline),encoding='utf-8')
        print(Path(str(target)+'.md'))
    return 1 if any(r['status']!='PASS' for r in rows) or any(r['kind']!='OK' for r in driver.results.values()) else 0


if __name__=='__main__':
    sys.exit(main())
