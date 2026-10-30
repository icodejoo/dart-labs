"""Launch the visual page, screencap on each SHOTMARK. 启动页面并在每个标记处截图。"""
import subprocess, sys, os, time
out = sys.argv[1]; os.makedirs(out, exist_ok=True)
pkg = 'com.icodejoo.mova.mova_example.smk'
subprocess.run(['adb', 'logcat', '-c'])
subprocess.run(['adb', 'shell', 'am', 'force-stop', pkg])
subprocess.run(['adb', 'shell', 'am', 'start', '-n', pkg + '/com.icodejoo.mova.mova_example.MainActivity'], stdout=subprocess.DEVNULL)
p = subprocess.Popen(['adb', 'logcat', '-s', 'flutter'], stdout=subprocess.PIPE, text=True, errors='replace')
t0 = time.time()
for line in p.stdout:
    if 'SHOTMARK|' in line:
        full = line.split('SHOTMARK|')[1].strip()
        name = full.split('|')[0]
        print(full, flush=True)
        if name in ('DONE',) or name.startswith('ERR'): break
        png = subprocess.run(['adb', 'exec-out', 'screencap', '-p'], capture_output=True).stdout
        open(os.path.join(out, name + '.png'), 'wb').write(png)
    if time.time() - t0 > 120: break
p.kill()
