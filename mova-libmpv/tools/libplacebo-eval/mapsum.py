#!/usr/bin/env python3
# usage: mapsum.py libmpv.map  -> 按归档/目标文件汇总保留段字节数
import re,sys,collections
f=open(sys.argv[1],errors="replace").read().split("\n")
start=next(i for i,l in enumerate(f) if l.startswith("Linker script and memory map"))
tot=collections.Counter(); arch=collections.Counter()
pend=None
rx1=re.compile(r"^ (\S+)\s+0x[0-9a-f]+\s+(0x[0-9a-f]+)\s+(\S.*)$")
rx2=re.compile(r"^\s+0x[0-9a-f]+\s+(0x[0-9a-f]+)\s+(\S.*)$")
for l in f[start:]:
    m=rx1.match(l)
    if m: sec,size,obj=m.groups(); pend=None
    else:
        if re.match(r"^ \S+$",l): pend=l.strip(); continue
        m=rx2.match(l)
        if m and pend: size,obj=m.groups(); sec=pend; pend=None
        else: continue
    s=int(size,16)
    if s==0 or sec.startswith((".debug",".comment",".note")): continue
    obj=obj.strip()
    tot[obj]+=s
    a=obj.split("(")[0].split("/")[-1] if "(" in obj else "mpv-objs"
    arch[a]+=s
print("== by archive");
for k,v in arch.most_common(15): print(f"{v:>10} {k}")
if len(sys.argv)>2:
    print("== top members of",sys.argv[2])
    for k,v in [(k,v) for k,v in tot.most_common() if sys.argv[2] in k][:int(sys.argv[3]) if len(sys.argv)>3 else 25]: print(f"{v:>10} {k.split(chr(47))[-1]}")
