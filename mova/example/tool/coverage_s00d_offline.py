"""Publish one device-free single-file Flutter contract run as raw evidence.

A failed/unfinished test process never gets a done status. No device tools,
Gradle, native application build or APK operation is used.
"""
import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess

TOOL=Path(__file__).resolve().parent
EXAMPLE=TOOL.parent

def records_from_output(content):
    records=[]
    for line in content.splitlines():
        match=re.search(r'(?:MATRIX_RECORD|COVERAGE) (\{.*\})',line)
        if match:
            row=json.loads(match[1])
            if isinstance(row,dict):records.append(row)
    return records

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('case',choices=['widgets','contract'])
    parser.add_argument('--output',required=True,type=Path)
    args=parser.parse_args()
    target=args.output.resolve()
    if not target.is_relative_to(EXAMPLE):parser.error('output must stay inside mova/example')
    flutter=shutil.which('flutter')
    if not flutter:parser.error('flutter is unavailable')
    command=[flutter,'test',f'test/s00d_{args.case}_test.dart','--concurrency=2','--no-pub']
    result=subprocess.run(command,cwd=EXAMPLE,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
    content=result.stdout.decode('utf-8',errors='replace')
    rows=records_from_output(content)
    target.parent.mkdir(parents=True,exist_ok=True)
    target.with_suffix('.log').write_text(content,encoding='utf-8')
    target.write_text(json.dumps(dict(status='done' if result.returncode==0 else 'error',
        origin='offline-flutter-single-file',command=command,exitCode=result.returncode,records=rows),
        ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(f'{args.case}: exit={result.returncode}, CHECK={sum(r.get("kind")=="CHECK" for r in rows)}; {target}')
    return result.returncode

if __name__=='__main__':raise SystemExit(main())
