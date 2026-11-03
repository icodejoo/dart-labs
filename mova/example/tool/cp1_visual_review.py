"""Review token-held keepAlive frames in the manually verified video-only ROI.

Retains pixel numbers and contact sheets; never derives motion from native vid.
The ROI excludes all page logs, status bars and the source's timestamp overlay.
"""
import argparse
from collections import Counter
import json
from pathlib import Path
import re

from PIL import Image, ImageChops, ImageDraw, ImageStat

ROI = (80, 360, 1000, 820)
SIZE = (1080, 2376)


def inspect_pair(row):
    capture = row.get('capture', {})
    token = capture.get('token')
    valid = row.get('captured') is True and row.get('phaseConfirmed') is True and token and all(
        capture.get(k, {}).get('token') == token for k in ('before', 'after', 'ack')) and capture.get('ack', {}).get('acknowledged') is True
    result = dict(marker=row.get('marker'), path=row.get('path'), motionPath=row.get('motionPath'),
                  phaseConfirmed=bool(valid), captureEndMs=row.get('captureEndMs'))
    if not valid:
        return dict(result, status='BLOCKED', reason='missing phase/foreground/capture confirmation'), []
    frames = [Image.open(row[k]).convert('RGB') for k in ('path', 'motionPath')]
    if any(f.size != SIZE for f in frames):
        return dict(result, status='BLOCKED', reason='video ROI geometry changed'), []
    crops = [f.crop(ROI) for f in frames]
    difference = ImageChops.difference(*crops)
    black = [all(hi == 0 for lo, hi in f.getextrema()) for f in crops]
    moving = difference.getbbox() is not None
    result.update(status='MEASURED', black=black, moving=moving,
        meanRgb=[ImageStat.Stat(f).mean for f in crops],
        meanAbsoluteDifference=ImageStat.Stat(difference).mean,
        changedPixels=sum(1 for pixel in difference.get_flattened_data() if any(pixel)),
        category='black' if all(black) else 'moving-picture' if moving else 'still-picture')
    return result, crops


def version(directories, output, label):
    rounds = []
    indexes = [p for directory in directories for p in directory.glob('*.round*.shots.jsonl')]
    for index in sorted(indexes, key=lambda p: p.stat().st_mtime):
        log = Path(str(index).replace('.shots.jsonl', '.log'))
        text = log.read_text(encoding='utf-8')
        rows = [json.loads(line) for line in index.read_text(encoding='utf-8').splitlines()
                if 'SHOT_ACK ' not in line]
        samples, tiles = [], []
        for row in rows:
            marker = re.search(r'\b(S7|S14) SHOT (\w+)', row['marker'])
            if not marker:
                continue
            sample, crops = inspect_pair(row)
            sample.update(scene=marker[1], phase=marker[2])
            samples.append(sample)
            tile = Image.new('RGB', (410, 128), 'white')
            draw = ImageDraw.Draw(tile)
            draw.text((4, 2), marker[0]+' '+sample.get('category', 'BLOCKED'), fill='black')
            for i, crop in enumerate(crops):
                tile.paste(crop.resize((200, 100)), (i*205, 24))
            tiles.append(tile)
        sheet = Image.new('RGB', (410*3, 128*((len(tiles)+2)//3)), '#dddddd')
        for i, tile in enumerate(tiles):
            sheet.paste(tile, ((i % 3)*410, (i//3)*128))
        sheet_path = output/f'{label}-{index.name.replace(".shots.jsonl", "")}.jpg'
        sheet.save(sheet_path, quality=95)
        native = {scene: re.findall(r'VERDICT '+scene+r' (PASS|FAIL) ([^\r\n]*)', text)
                  for scene in ('S7', 'S14')}
        scenes = {}
        for scene, phases in [('S7', list(map(str, range(1, 21)))),
                              ('S14', ['normal', 'holding1', 'holding2', 'restored'])]:
            selected = [s for s in samples if s['scene'] == scene]
            complete = [s['phase'] for s in selected] == phases and all(s['status'] == 'MEASURED' for s in selected)
            native_ok = len(native[scene]) == 1 and native[scene][0][0] == 'PASS'
            if scene == 'S7':
                native_ok = native_ok and re.findall(r'S7 hwdec=([^\s]+)', text) == ['mediacodec-copy']
            else:
                held = [s for s in selected if s['phase'].startswith('holding')]
                native_ok = native_ok and len(held) == 2 and all('vid=no' in s['marker'] for s in held)
                native_ok = native_ok and any('entered=true' in s['marker'] for s in held)
            moving_phases = selected if scene == 'S7' else [s for s in selected if s['phase'] in ('normal', 'restored')]
            pixel_ok = all(s.get('moving') is True and s.get('black') == [False, False] for s in moving_phases)
            scenes[scene] = dict(status='BLOCKED' if not complete else 'PASS' if native_ok and pixel_ok else 'FAIL',
                complete=complete, native=native[scene], motionPairs=sum(s.get('moving') is True for s in moving_phases),
                requiredMotionPairs=20 if scene == 'S7' else 2,
                holding={s['phase']: s.get('category') for s in selected if s['phase'].startswith('holding')})
        rounds.append(dict(index=str(index), log=str(log), contactSheet=str(sheet_path),
                           completed='AUTORUN DONE' in text, scenes=scenes, samples=samples))
    return dict(source=list(map(str, directories)), rounds=rounds,
                counts={s: dict(Counter(r['scenes'][s]['status'] for r in rounds)) for s in ('S7', 'S14')})


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--baseline', type=Path, required=True)
    p.add_argument('--current', type=Path)
    p.add_argument('--baseline-supplement', type=Path, action='append', default=[])
    p.add_argument('--current-supplement', type=Path, action='append', default=[])
    p.add_argument('--out', type=Path, required=True)
    args = p.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    result = dict(roi=ROI, expectedSize=SIZE,
        method='Video-only ROI manually verified from the original screenshot; exact pixel change plus contact-sheet review. Holding appearance compared with CP0.',
        baseline=version([args.baseline, *args.baseline_supplement], args.out, 'cp0'), status='BLOCKED')
    if args.current:
        result['current'] = version([args.current, *args.current_supplement], args.out, 'cp1')
        decisions, selections = {}, {}
        for scene in ('S7', 'S14'):
            # Only incomplete fixture captures may be replaced by explicit
            # supplemental attempts. Complete native/pixel FAILs stay selected.
            selected = {v: [r for r in result[v]['rounds'] if r['completed'] and r['scenes'][scene]['complete']][:5]
                        for v in ('baseline', 'current')}
            selections[scene] = {v: [r['index'] for r in selected[v]] for v in selected}
            complete = all(len(selected[v]) == 5 for v in selected)
            current = dict(Counter(r['scenes'][scene]['status'] for r in selected['current']))
            holdings_equal = all(a['scenes'][scene]['holding'] == b['scenes'][scene]['holding']
                                 for a, b in zip(selected['baseline'], selected['current']))
            decisions[scene] = 'BLOCKED' if not complete else (
                'PASS' if current == {'PASS': 5} and holdings_equal else 'FAIL')
        result['decisions'] = decisions
        result['selections'] = selections
        result['status'] = 'FAIL' if 'FAIL' in decisions.values() else 'PASS' if all(s == 'PASS' for s in decisions.values()) else 'BLOCKED'
    target = args.out/'visual-review.json'
    target.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps(dict(status=result['status'], baseline=result['baseline']['counts'],
                         current=result.get('current', {}).get('counts'), evidence=str(target)), ensure_ascii=False))


if __name__ == '__main__':
    main()
