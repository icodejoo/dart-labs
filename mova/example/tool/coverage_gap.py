"""Gap device driver. Import/offline inspection never accesses adb.

prepare builds the independent release entry; other groups launch that APK.
Use a fresh run ID; generated fixtures and all evidence remain in tool evidence.
"""
import argparse
import base64
from datetime import datetime
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
import urllib.parse
import urllib.request

import run_matrix as matrix


class Blocked(Exception):
    pass


class GapDriver(matrix.Driver):
    def screen(self):
        window=self.adb('shell','dumpsys','window')
        if not matrix.is_unlocked(window):
            raise Blocked('device must be awake and unlocked; rendering evidence blocked')
        return window

    def note(self, kind, detail, case='gap:HARNESS.driver'):
        line = f'[MOVA-COV] {datetime.now().astimezone().isoformat(timespec="milliseconds")} <run={self.logical_run_id}> <case={case}> {kind} {detail}'
        print(line, flush=True)
        with self.log.open('a', encoding='utf-8') as stream:
            stream.write(line + '\n')

    def http(self, path='/', **query):
        url = 'http://127.0.0.1:18086' + path + '?' + urllib.parse.urlencode(query)
        self.note('CALL', json.dumps({'url': url}))
        try:
            with urllib.request.urlopen(url, timeout=8) as response:
                result = json.load(response)
            self.note('RET', json.dumps({'http': 200, 'phase': result['phase'], 'rows': len(result['rows'])}))
            return result
        except Exception as error:
            self.note('RET', json.dumps({'exception': str(error)}))
            raise

    def mark(self, name):
        return self.http('/mark', name=name)

    def capture(self, case, label):
        """Save immediate window/audio evidence and lossless screenshot."""
        name = re.sub(r'[^A-Za-z0-9_.-]', '_', case + '-' + label)
        for suffix, command in [('window.txt', ('shell', 'dumpsys', 'window')),
                                ('audio.txt', ('shell', 'dumpsys', 'audio')),
                                ('audioflinger.txt', ('shell', 'dumpsys', 'media.audio_flinger')),
                                ('png', ('exec-out', 'screencap', '-p'))]:
            path = self.out / (name + '.' + suffix)
            path.write_bytes(self.adb(*command, binary=True))
            if suffix == 'png':
                self.note('SHOT', str(path), case)

    def wait(self, predicate, seconds=60):
        end = time.monotonic() + seconds
        while time.monotonic() < end:
            try:
                if predicate():
                    return
            except (OSError, ValueError):
                pass  # Transport not ready yet; every failed HTTP RET is logged.
            time.sleep(.2)
        raise RuntimeError('HARNESS watchdog: no expected device handshake')

    def launch(self):
        self.adb('forward', 'tcp:18086', 'tcp:18086')
        self.mappings.append(('forward', 18086))
        self.adb('reverse', 'tcp:18085', 'tcp:18085')
        self.mappings.append(('reverse', 18085))
        self.adb('shell', 'am', 'force-stop', matrix.PACKAGE)
        self.adb('shell', 'am', 'start', '-n', matrix.PACKAGE + '/com.icodejoo.mova.mova_example.MainActivity')
        self.wait(lambda: self.http()['phase'] == 'idle')
        pid = self.adb('shell', 'pidof', matrix.PACKAGE).strip()
        if not pid or not pid.isdigit():
            raise RuntimeError('cannot resolve single app pid')
        stream = (self.out / 'gap.logcat').open('wb')
        argv = ['adb', '-s', self.serial, 'logcat', '--pid=' + pid, '-v', 'threadtime']
        self.note('CALL', json.dumps(argv))
        proc = subprocess.Popen(argv, stdout=stream, stderr=subprocess.STDOUT,
                                creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0)
        self.children.append((proc, stream))
        self.note('RET', f'logcat pid={proc.pid} started')

    def media(self, fixtures):
        if not (fixtures / 'generation.json').is_file():
            raise Blocked('run prepare first; fixtures missing')
        stream = (self.out / 'media.driver.log').open('w', encoding='utf-8')
        argv = [sys.executable, '-B', str(matrix.TOOL / 'coverage_gap_media.py'), '--out', str(fixtures), '--reuse']
        self.note('CALL', json.dumps(argv))
        proc = subprocess.Popen(argv, stdout=stream, stderr=subprocess.STDOUT,
                                creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0)
        self.children.append((proc, stream))
        self.note('RET', f'media pid={proc.pid} started')
        def ready():
            if proc.poll() is not None:
                raise RuntimeError('media server exited')
            with urllib.request.urlopen('http://127.0.0.1:18085/status', timeout=1) as r:
                return r.status == 200
        self.wait(ready)

    def system_action(self, mode):
        """Only act after the device emits its hostAction handshake."""
        self.capture('gap:G2.' + mode, 'before')
        if mode == 'screen':
            self.adb('shell', 'input', 'keyevent', '223')  # SLEEP, never toggle.
            self.wait(lambda: 'mWakefulness=Asleep' in self.adb('shell', 'dumpsys', 'power'))
            self.capture('gap:G2.3.screen', 'locked')
            self.mark('screen-active')
            self.wait(lambda: 'screen-sampled' in self.http()['marks'])
            self.adb('shell', 'input', 'keyevent', '224')
            # Secure keyguard needs its owner. No artificial unlock succeeds by timeout.
            try:
                self.wait(lambda: matrix.is_unlocked(self.adb('shell', 'dumpsys', 'window')), seconds=60)
            except RuntimeError as error:
                raise Blocked('screen awake but locked: owner must unlock and rerun') from error
            self.mark('screen-restored')
        elif mode == 'focus':
            if self.gsm:
                if self.adb('shell', 'getprop', 'ro.kernel.qemu').strip() != '1':
                    raise Blocked('adb emu gsm call is emulator-only; physical device conditional case BLOCKED')
                try:
                    self.adb('emu', 'gsm', 'call', '15555215554')
                    self.capture('gap:G2.1.emulatorCall', 'incoming-call')
                    self.mark('focus-active')
                    self.wait(lambda: 'focus-sampled' in self.http()['marks'])
                finally:
                    self.adb('emu', 'gsm', 'cancel', '15555215554')
                self.mark('focus-restored')
                return
            component = os.environ.get('MOVA_GAP_FOCUS_COMPONENT')
            if not component:
                raise Blocked('set MOVA_GAP_FOCUS_COMPONENT to an installed player activity that starts audible playback')
            try:
                self.adb('shell', 'am', 'start', '-n', component, '-a', 'android.intent.action.VIEW',
                         '-d', 'http://127.0.0.1:18085/long.mp4', '-t', 'video/mp4')
                self.capture('gap:G2.1.focus', 'competitor')
                self.mark('focus-active')
                self.wait(lambda: 'focus-sampled' in self.http()['marks'])
            finally:
                self.adb('shell', 'am', 'force-stop', component.split('/')[0])
            self.adb('shell', 'am', 'start', '-n', matrix.PACKAGE + '/com.icodejoo.mova.mova_example.MainActivity')
            self.mark('focus-restored')
        elif mode == 'network':
            # Save the effective settings and always restore in finally.
            wifi = self.adb('shell', 'settings', 'get', 'global', 'wifi_on').strip()
            data = self.adb('shell', 'settings', 'get', 'global', 'mobile_data').strip()
            airplane = self.adb('shell', 'settings', 'get', 'global', 'airplane_mode_on').strip()
            if wifi not in ('0', '1') or data not in ('0', '1') or airplane not in ('0', '1'):
                raise Blocked('cannot read radio settings for exact restoration')
            (self.out / 'connectivity.before.txt').write_text(self.adb('shell','dumpsys','connectivity'),encoding='utf-8')
            try:
                self.adb('shell', 'svc', 'data', 'enable')
                self.adb('shell', 'svc', 'wifi', 'disable')
                self.capture('gap:G2.2.network', 'cellular')
                (self.out / 'connectivity.cellular.txt').write_text(self.adb('shell', 'dumpsys', 'connectivity'), encoding='utf-8')
                self.adb('shell', 'cmd', 'connectivity', 'airplane-mode', 'enable')
                (self.out / 'connectivity.airplane.txt').write_text(self.adb('shell','dumpsys','connectivity'),encoding='utf-8')
                self.capture('gap:G2.2.network', 'airplane')
                self.mark('network-active')
                self.wait(lambda: 'network-sampled' in self.http()['marks'])
            finally:
                self.adb('shell', 'cmd', 'connectivity', 'airplane-mode', 'enable' if airplane == '1' else 'disable')
                self.adb('shell', 'svc', 'wifi', 'enable' if wifi == '1' else 'disable')
                self.adb('shell', 'svc', 'data', 'enable' if data == '1' else 'disable')
            restored=[self.adb('shell','settings','get','global',key).strip()
                      for key in ('wifi_on','mobile_data','airplane_mode_on')]
            if restored!=[wifi,data,airplane]:
                raise RuntimeError('HARNESS radio settings did not restore exactly: '+str(restored))
            (self.out / 'connectivity.restored.txt').write_text(self.adb('shell','dumpsys','connectivity'),encoding='utf-8')
            self.mark('network-restored')
            # Connectivity dumps are essential: a successful svc command is not a transition.
            self.note('EXPECT', 'Wi-Fi to cellular and airplane routes visibly change in native connectivity dumps', 'gap:G2.2.network')
            self.note('ACTUAL', 'inspect connectivity.cellular.txt and screenshots', 'gap:G2.2.network')
            self.note('VERDICT', 'BLOCKED manual native route confirmation', 'gap:G2.2.network')

    def run_cases(self, args):
        self.http('/run', group=args.group, run=args.run_id, iterations=args.iterations, seed=args.seed, actions=args.actions, skins=args.skins)
        seen = 0
        shots = set()
        acted = False
        deadline = time.monotonic() + args.timeout
        product_rows = []
        all_rows = []
        while time.monotonic() < deadline:
            data = self.http('/poll', since=seen)
            fresh = data['rows']
            all_rows.extend(fresh)
            data['rows'] = all_rows
            with (self.out / 'gap.jsonl').open('a',encoding='utf-8') as stream:
                for row in fresh:
                    stream.write(json.dumps(row,ensure_ascii=False)+'\n')
            for row in fresh:
                case, kind, payload = row['case'], row['kind'], row['data']
                if kind == 'VERDICT':
                    product_rows.append(row)
                    if payload['status'] == 'FAIL':
                        self.capture(case, 'failure')
                        recent = [r for r in data['rows'][:seen+len(fresh)] if r['kind'] == 'EVENT'][-50:]
                        (self.out / ('recent-' + str(seen) + '.json')).write_text(json.dumps(recent, ensure_ascii=False, indent=2), encoding='utf-8')
                        if payload.get('evidenceToken'):
                            self.mark(payload['evidenceToken'])
                if kind == 'SHOT' and payload['name'] not in shots:
                    name = payload['name']
                    self.capture(case, name)
                    shots.add(name)
                    self.mark(('before-shot-' if name.startswith('before-hold-') else 'shot-') + name.rsplit('-', 1)[1])
                if kind == 'STEP' and isinstance(payload, dict) and payload.get('hostAction') and not acted:
                    acted = True
                    self.system_action(payload['hostAction'])
            seen = len(data['rows'])
            if not data['marks'] or 'late-error-sent' not in data['marks']:
                with urllib.request.urlopen('http://127.0.0.1:18085/status', timeout=2) as response:
                    if json.load(response)['late_error']:
                        self.mark('late-error-sent')
            if data['phase'] == 'done':
                (self.out / 'gap.json').write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding='utf-8')
                if not product_rows:
                    raise RuntimeError('no per-case verdicts')
                harness = [r for r in data['rows'] if r['kind'] == 'ERROR']
                self.gap_harness = harness
                self.gap_verdicts = [dict(case=r['case'], **r['data']) for r in product_rows]
                self.gap_completed = True
                (self.out / 'harness.json').write_text(json.dumps(harness, ensure_ascii=False, indent=2), encoding='utf-8')
                return 2 if harness else 1 if any(r['data']['status'] != 'PASS' for r in product_rows) else 0
            time.sleep(.25)
        raise RuntimeError('group watchdog expired')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('group', choices=['prepare', 'assumptions', 'lifecycle', 'local', 'formats', 'random', 'focus', 'focus-gsm', 'network', 'screen', 'skin', 'build-variants'])
    parser.add_argument('--run-id', default=datetime.now().strftime('%Y%m%d-%H%M%S'))
    parser.add_argument('--iterations', type=int, default=3)
    parser.add_argument('--seed', type=int, default=20261028)
    parser.add_argument('--actions', type=int, default=80)
    parser.add_argument('--skins', default='default,bilibili,douyin,minimal,mini', help='skin group only: comma-separated skins to run')
    parser.add_argument('--timeout', type=int, default=1800)
    parser.add_argument('--network-url', default=os.environ.get('MOVA_GAP_NETWORK_URL'))
    args = parser.parse_args()
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]{0,60}', args.run_id):
        parser.error('unsafe run ID')
    manifest = json.loads(matrix.MANIFEST.read_text(encoding='utf-8'))
    manifest['ports'] = [18085, 18086]
    manifest['build']['argv'][-1] = 'lib/main_coverage_gap.dart'
    if args.network_url:
        define=base64.b64encode(('GAP_NETWORK_URL='+args.network_url).encode()).decode()
        manifest['build']['argv'].append('-Pdart-defines='+define)
    # Driver namespaces are separate per group; fixtures belong to prepare.
    fixtures = matrix.TOOL / 'coverage_evidence' / ('matrix-' + args.run_id + '-gap-prepare') / 'fixtures'
    driver_args = argparse.Namespace(run_id=args.run_id + '-gap-' + args.group)
    driver = GapDriver(driver_args, manifest)
    driver.logical_run_id=args.run_id
    driver.gsm=args.group=='focus-gsm'
    driver.gap_verdicts=[]
    driver.gap_harness=[]
    driver.gap_completed=False
    code = 2
    try:
        if args.group == 'build-variants':
            for ident, commands in {
                'G1.1': ['cd android; .\\gradlew.bat -I ../tool/coverage_gap_variants.init.gradle -Pgap-abis=armeabi-v7a,arm64-v8a,x86_64 -Ptarget-platform=android-arm,android-arm64,android-x64 -Ptarget=lib/main_coverage_gap.dart :app:assembleRelease --info',
                         'x86: Flutter AOT release is not supported; schedule a separate debug build/device and label BLOCKED for release ABI. Missing slim JNI libraries must remain BLOCKED.'],
                'G1.2': ['flutter build apk --release --target lib/main_coverage_gap.dart --obfuscate --split-debug-info=tool/coverage_evidence/gap-symbols',
                         'cd android; .\\gradlew.bat -I ../tool/coverage_gap_variants.init.gradle -Pgap-abis=arm64-v8a -Ptarget-platform=android-arm64 -Ptarget=lib/main_coverage_gap.dart -Pdart-obfuscation=true -Psplit-debug-info=../tool/coverage_evidence/gap-symbols :app:assembleRelease --info'],
            }.items():
                driver.note('BEGIN', 'manual build variant; run commands from example/', 'gap:' + ident + '.build')
                driver.note('EXPECT', 'native libraries match ABI; APK installs; formats/local/PiP/volume/brightness pass; R8 minifyReleaseWithR8 output and mapping.txt retained', 'gap:' + ident + '.build')
                driver.note('ACTUAL', json.dumps(commands), 'gap:' + ident + '.build')
                driver.note('VERDICT', 'BLOCKED manual build/device/ABI scheduling required; never substitute arm64-only coverage.init.gradle', 'gap:' + ident + '.build')
                driver.note('END', 'commands prepared', 'gap:' + ident + '.build')
            driver.gap_completed=True
            driver.gap_verdicts=[dict(case='gap:'+i+'.build',status='BLOCKED',reason='manual ABI/build scheduling') for i in ('G1.1','G1.2')]
            code=1
            return code
        driver.preflight()
        if args.group == 'prepare':
            driver.command([sys.executable, '-B', matrix.TOOL / 'coverage_gap_media.py', '--out', fixtures, '--generate-only'], timeout=7200)
            driver.build()
            driver.gap_completed=True
            code=0
            return code
        driver.media(fixtures)
        driver.launch()
        code = driver.run_cases(args)
    except Blocked as error:
        driver.note('EXPECT', 'device/service prerequisites satisfied')
        driver.note('ACTUAL', str(error))
        driver.note('VERDICT', 'BLOCKED ' + str(error))
        driver.gap_verdicts.append(dict(case='gap:'+args.group+'.prerequisite',status='BLOCKED',reason=str(error)))
        code = 1
    except Exception as error:
        driver.note('ERROR', 'kind=HARNESS ' + str(error))
        driver.gap_harness.append(str(error))
        code = 2
    finally:
        driver.cleanup()
        if driver.results:
            driver.gap_harness.append(driver.results)
        (driver.out / 'gap-result.json').write_text(json.dumps(dict(
            run_id=args.run_id,group=args.group,completed=driver.gap_completed,
            verdicts=driver.gap_verdicts,harness=driver.gap_harness),ensure_ascii=False,indent=2),encoding='utf-8')
    return code


if __name__ == '__main__':
    sys.exit(main())
