"""Summarize zero-copy matrix evidence: HWM_ROW lines plus per-probe CPU, decoder name and screencap pixels.

汇总零拷贝矩阵证据：HWM_ROW、每个 probe 的 CPU / 解码器名 / 截图像素。
用法: python zero_copy_report.py A-codec [A-shot ...]
"""
import re
import statistics
import sys
from pathlib import Path
from PIL import Image

OUT = Path(__file__).resolve().parent / 'coverage_evidence' / 'zero-copy'


def rows(name):
    for line in (OUT / f'{name}.log').read_text(encoding='utf-8', errors='replace').splitlines():
        m = re.search(r'HWM_ROW (\S+) (.*)$', line)
        if m:
            yield m.group(1), dict(re.findall(r'(\w+)=(\S+)', m.group(2))), m.group(2)


def rects(name):
    out = {}
    for line in (OUT / f'{name}.log').read_text(encoding='utf-8', errors='replace').splitlines():
        m = re.search(r'HWM_(?:PROBE|SHOT) (\S+) rect=(\d+),(\d+),(\d+),(\d+)', line)
        if m:
            out[m.group(1)] = tuple(int(x) for x in m.groups()[1:])
    return out


def pixels(png, rect):
    """mean luma, colorful fraction of the crop / 裁剪区域平均亮度与彩色占比"""
    if not png.exists():
        return None
    im = Image.open(png).convert('RGB')
    if rect:
        im = im.crop(rect)
    px = list(im.getdata())[::5]
    luma = sum(0.299 * r + 0.587 * g + 0.114 * b for r, g, b in px) / len(px)
    col = sum(1 for r, g, b in px if max(r, g, b) - min(r, g, b) > 60) / len(px)
    return round(luma, 1), round(col, 3)


def cpu(pid_id):
    f = OUT / f'hwm-{pid_id}.top.txt'
    if not f.exists():
        return {}
    blocks = f.read_text(encoding='utf-8', errors='replace').split('Tasks:')[1:]
    res = {'busy': [], 'app': [], 'codec': [], 'sf': []}
    for b in blocks[1:]:
        m = re.search(r'(\d+)%cpu.*?(\d+)%idle', b)
        if m:
            res['busy'].append(int(m.group(1)) - int(m.group(2)))
        for line in b.splitlines():
            cols = line.split()
            if len(cols) >= 9:
                try:
                    v = float(cols[8])
                except ValueError:
                    continue
                if 'mova_example' in line:
                    res['app'].append(v)
                elif 'media.codec' in line:
                    res['codec'].append(v)
                elif 'surfaceflinger' in line:
                    res['sf'].append(v)
    return {k: (round(statistics.median(v), 1) if v else None) for k, v in res.items()}


def decoder(pid_id):
    f = OUT / f'hwm-{pid_id}.rm.txt'
    if not f.exists():
        return 'n/a'
    names = sorted(set(re.findall(r'Name:\s*(\S+)', f.read_text(encoding='utf-8', errors='replace'))))
    return ','.join(names) or 'none'


if __name__ == '__main__':
    for name in sys.argv[1:]:
        print(f'## {name}')
        rc = rects(name)
        for scen, kv, raw in rows(name):
            i = kv.get('id', '')
            extra = ''
            if scen == 'codec':
                px = pixels(OUT / f'hwm-{i}.png', rc.get(i))
                extra = f' | decoder={decoder(i)} cpu={cpu(i)} screencap(luma,colorful)={px}'
            elif scen in ('shot', 'cutover', 'mini', 'pip', 'bg'):
                pxs = {}
                for tag in ('', '-ad', '-content', '-inpage', '-route', '-after', '-back', '-manual'):
                    p = OUT / f'hwm-{i}{tag}.png'
                    if p.exists():
                        pxs[tag or 'shot'] = pixels(p, rc.get(i + tag))
                extra = f' | screencap={pxs}'
            print(f'{scen} {raw}{extra}')
