#!/usr/bin/env python3
"""Normalised per-function disassembly diff between two SkyLight builds.

Absolute addresses shift between builds, so a raw diff is all noise. This strips
the address/raw-byte columns and rewrites absolute operands as symbol+offset or a
placeholder, leaving only the instruction semantics to compare.
"""
import re, subprocess, sys, difflib

import os
LIB = os.environ.get('LIB','System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight')
BINS = {'5':'beta5-root/'+LIB, '6':'beta6-root/'+LIB}

def syms(tag):
    out = subprocess.run(['nm','-n',BINS[tag]],capture_output=True,text=True).stdout
    rows=[]
    for l in out.splitlines():
        # ObjC method symbols contain spaces -- split only the address and type,
        # keep the rest of the line as the name. An earlier version used a plain
        # 3-field split and silently reported every ObjC method as NOT FOUND.
        m=re.match(r'^([0-9a-f]{16}) (\S) (.+)$', l)
        if m: rows.append((int(m.group(1),16), m.group(2), m.group(3)))
    return rows

def span(rows,name):
    for i,(a,t,n) in enumerate(rows):
        if n==name:
            for a2,t2,n2 in rows[i+1:]:
                if a2>a and t2.lower() in 'tt': return a,a2
            return a,a+0x4000
    return None

def disas(tag,lo,hi):
    r=subprocess.run(['xcrun','llvm-objdump','-d','--no-show-raw-insn',
                      f'--start-address={hex(lo)}',f'--stop-address={hex(hi)}',BINS[tag]],
                     capture_output=True,text=True).stdout
    out=[]
    for l in r.splitlines():
        m=re.match(r'\s*[0-9a-f]+:\s+(.*)$',l)
        if not m: continue
        ins=m.group(1).strip()
        # adrp/data-page operands are symbolised by NEAREST symbol, so an
        # unrelated data shift renames them. That is not a code change -- strip
        # the annotation entirely or every build looks different.
        ins=re.sub(r'\s*<[^>]*>\s*$','',ins)
        ins=re.sub(r'0x[0-9a-f]{6,}','<abs>',ins)          # absolute addrs
        ins=re.sub(r'#0x[0-9a-f]+','#<imm>',ins)            # large immediates
        ins=re.sub(r'<\+?[0-9]+>','<off>',ins)
        out.append(ins)
    return out

def main(name):
    r5,r6=syms('5'),syms('6')
    s5,s6=span(r5,name),span(r6,name)
    if not s5 or not s6:
        print(f'{name}: NOT FOUND (b5={bool(s5)} b6={bool(s6)})'); return
    d5=disas('5',*s5); d6=disas('6',*s6)
    same = d5==d6
    print(f'{"SAME " if same else "DIFF "} {name}')
    print(f'    beta5 {hex(s5[0])} size {s5[1]-s5[0]:#x} insns {len(d5)}')
    print(f'    beta6 {hex(s6[0])} size {s6[1]-s6[0]:#x} insns {len(d6)}')
    if not same:
        diff=list(difflib.unified_diff(d5,d6,'beta5','beta6',lineterm='',n=3))
        add=sum(1 for l in diff if l.startswith('+') and not l.startswith('+++'))
        rem=sum(1 for l in diff if l.startswith('-') and not l.startswith('---'))
        print(f'    +{add} / -{rem} instructions')
        for l in diff[:int(sys.argv[2]) if len(sys.argv)>2 else 60]:
            print('      '+l)
    print()

for n in sys.argv[1].split(','):
    main(n)
