"""把页面日志里的 PHASE 窗口，和 CPU 采样 csv、服务器流量日志对齐，输出每窗口的 CPU% 与流量。
用法: python phase_report.py <page.log> <cpu.csv> <server.log>"""
import re, sys
from datetime import datetime

def t(s):  # HH:MM:SS.mmm -> 秒
    h, m, x = s.split(':'); return int(h) * 3600 + int(m) * 60 + float(x)

page, cpu_csv, srv = sys.argv[1:4]
phases = {}  # 窗口名可能重复出现（多轮），按出现顺序编号 name#1、name#2 ...
open_at = {}
count = {}
for line in open(page, encoding='utf-8'):
    m = re.search(r'\] (\d\d:\d\d:\d\d\.\d+) +\d+ms PHASE (\S+) (begin|end)', line)
    if not m: continue
    name, kind, ts = m.group(2), m.group(3), t(m.group(1))
    if kind == 'begin':
        open_at[name] = ts
    elif name in open_at:
        count[name] = count.get(name, 0) + 1
        phases['%s#%d' % (name, count[name])] = {'begin': open_at.pop(name), 'end': ts}
cpu = []
for line in open(cpu_csv):
    a = line.strip().split(',')
    if len(a) >= 2: cpu.append((t(a[0]), float(a[1])))
def cpu_at(x):
    best = min(cpu, key=lambda p: abs(p[0] - x)); return best
bytes_lines = []
for line in open(srv, encoding='utf-8'):
    m = re.match(r'(\d\d:\d\d:\d\d\.\d+) c(\d+) BYTES (\d+)', line)
    if m: bytes_lines.append((t(m.group(1)), int(m.group(2)), int(m.group(3))))
print('%-22s %8s %8s %10s %10s' % ('phase', 'wall_s', 'cpu_s', 'cpu_pct', 'KB/s'))
for name, d in phases.items():
    if 'begin' not in d or 'end' not in d: continue
    b, e = d['begin'], d['end']
    (tb, cb), (te, ce) = cpu_at(b), cpu_at(e)
    wall = te - tb; pct = (ce - cb) / wall * 100 if wall > 0 else float('nan')
    # 流量：取窗口内行数最多的连接，窗口末尾累计值 - 窗口开头之前最后一次累计值
    inwin = [x for x in bytes_lines if b <= x[0] <= e]
    kbps = float('nan')
    if inwin:
        cid = max({x[1] for x in inwin}, key=lambda c: sum(1 for x in inwin if x[1] == c))
        before = [x[2] for x in bytes_lines if x[1] == cid and x[0] < b]
        last = [x[2] for x in inwin if x[1] == cid][-1]
        kbps = (last - (before[-1] if before else 0)) / (e - b) / 1024
    print('%-22s %8.1f %8.2f %9.1f%% %10.1f' % (name, wall, ce - cb, pct, kbps))
