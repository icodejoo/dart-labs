"""Append measured batches and revise the numbered ledger without losing history.

追加实测批次并修订编号台账，保留历史记录。
"""
from pathlib import Path
import json
import re
import sys
from collections import Counter

ROOT = Path(__file__).resolve().parents[2]
RESULT = ROOT / 'doc/plans/2026-10-27-device-coverage-results.md'
EVIDENCE = ROOT / 'example/tool/coverage_evidence'


def update(title, changes, notes):
    """Apply explicit verdicts, then derive counts from the complete ledger.

    写入明确结论，再从完整台账统计数量。
    """
    text = RESULT.read_text(encoding='utf-8')
    for ident, verdict, detail in changes:
        detail = detail.replace('|', '/')
        pattern = r'^\| '+re.escape(ident)+r' \| (PASS|FAIL|BLOCKED) \| .*? \|$'
        text, n = re.subn(pattern, lambda m: f'| {ident} | {verdict} | {detail} |', text, flags=re.M)
        if n != 1:
            raise ValueError((ident,n))
    text += '\n## '+title+'\n\n'+'\n'.join(notes)+'\n'
    counts = Counter(re.findall(r'^\| (?:[ACUFN]\d+|E\.[A-Za-z]+|E[12]) \| (PASS|FAIL|BLOCKED) \|',text,re.M))
    summary = f"当前有效总计 {sum(counts.values())}：PASS {counts['PASS']} / FAIL {counts['FAIL']} / BLOCKED {counts['BLOCKED']}。后续批次更新台账；历史计数仅为当时快照。"
    text = re.sub(r'\n> 当前有效总计 .*?\n','\n',text)
    text = text.replace('\n', '\n\n> '+summary+'\n',1)
    RESULT.write_text(text,encoding='utf-8')
    print(summary)


def journal(name):
    """Read only this command's slice from an accumulating device journal.

    从累计日志中只读取本次命令区间。
    """
    rows=json.loads((EVIDENCE/(name+'.json')).read_text(encoding='utf-8'))['records']
    start=max((i for i,r in enumerate(rows) if r['kind']=='BEGIN'),default=0)
    return rows[start:]


if __name__ == '__main__':
    spec=json.loads(Path(sys.argv[1]).read_text(encoding='utf-8'))
    update(spec['title'],spec['changes'],spec['notes'])
