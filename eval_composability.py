#!/usr/bin/env python3
# Encoder-agnostic composition experiment (Table: tab:compose in the paper).
# Run:  python3 eval_composability.py
import sys; sys.path.insert(0,"/sessions/brave-keen-faraday/mnt/32bit_RISCV")
import math, random, struct, zlib
import golden_compress as gc
N=gc.N; MASK=gc.MASK
def lec_words(b):
    bits=32; prev=b[0]
    for w in b[1:]:
        d=w-prev; n=abs(d).bit_length()
        plen=2 if n==0 else (3 if n<=5 else n-2); bits+=plen+n; prev=w
    return math.ceil(bits/32)
def d16_words(b):
    ok=all(-32768 <= (lambda d: d-(1<<32) if d>=(1<<31) else d)((b[k]-b[k-1])&MASK) <= 32767 for k in range(1,N))
    return 1+1+math.ceil(15*16/32) if ok else 99
def L(b):
    return {"ZERO":len(gc.comp_zero_hw(b)),"RLE":len(gc.comp_rle_hw(b)),
            "DELTA":len(gc.comp_delta_hw(b)),"DELTA16":d16_words(b),
            "LEC":lec_words(b),"RAW":N}
ORDER=["ZERO","RLE","DELTA","DELTA16","LEC","RAW"]
def pick(l,allowed):
    best=None
    for m in ORDER:
        if m in allowed and (best is None or l[m]<l[best]): best=m
    return best
def blocks(p):
    ws=gc.load_hex(p); return [ws[i:i+N] for i in range(0,len(ws)-N+1,N)]
rng=random.Random(0xC0FFEE)
def zh(n):
    o=[]
    for _ in range(n):
        b=[0]*N
        for p in rng.sample(range(N),rng.randint(1,4)): b[p]=rng.randint(1,MASK)
        o.append(b)
    return o
def rp(n):
    o=[]
    for _ in range(n):
        nr=rng.randint(2,4); b=[]
        for _ in range(nr): b+=[rng.randint(0,MASK)]*(N//nr)
        o.append((b+[b[-1]]*N)[:N])
    return o
def sv(n):
    o=[]
    for _ in range(n):
        b=[rng.randint(0,100000)]
        for _ in range(N-1): b.append((b[-1]+rng.randint(-8,8))&MASK)
        o.append(b)
    return o
def rd(n): return [[rng.randint(0,MASK) for _ in range(N)] for _ in range(n)]
def mx(n):
    o=[]
    while len(o)<n:
        o+=zh(1); o+=rp(1); o+=sv(1); o+=rd(1)
    return o[:n]
S={"zero_heavy":zh(128),"repetitive":rp(128),"slow_vary":sv(128),"random":rd(128)}
S["synth_mixed"]=mx(128)
R={n:blocks(f) for n,f in [("temperature","real_temp.hex"),("light","real_light.hex"),
                            ("voltage","real_volt.hex"),("mixed","real_mixed.hex")]}
A4={"ZERO","RLE","DELTA","RAW"}; A5=A4|{"LEC"}; A4D={"ZERO","RLE","DELTA","DELTA16","RAW"}
def agg(bs,allowed):
    return len(bs)*N/sum(L(b)[pick(L(b),allowed)] for b in bs)
def lecpure(bs): return len(bs)*N/sum(lec_words(b) for b in bs)

print("="*86)
print("A) ENCODER-AGNOSTIC SCALING: same selector, bigger library")
print("="*86)
print(f"{'corpus':<14}{'4-mode':>9}{'+DELTA16':>10}{'+LEC(5)':>10}{'LEC alone':>11}{'sel. gain':>11}")
for nm,g in [("REAL (2048)",[b for v in R.values() for b in v]),
             ("SYNTH (640)",[b for v in S.values() for b in v]),
             ("ALL (2688)",[b for v in R.values() for b in v]+[b for v in S.values() for b in v])]:
    print(f"{nm:<14}{agg(g,A4):>9.2f}{agg(g,A4D):>10.2f}{agg(g,A5):>10.2f}{lecpure(g):>11.2f}{agg(g,A5)/lecpure(g):>10.3f}x")
print()
print("  -> On real data alone the selector adds little over LEC (LEC is near-universal there).")
print("  -> On the full corpus the selector is what stops LEC's collapse. Detail:")
r=S["random"]
print(f"     random-only:  LEC alone {lecpure(r):.3f}x (INFLATES {1/lecpure(r):.2f}x) | LEC-in-selector {agg(r,A5):.3f}x")

print()
print("="*86)
print("B) WHERE THE 4-MODE LIBRARY LOSES: RAW blocks and the DELTA-16 gap")
print("="*86)
allreal=[b for v in R.values() for b in v]
d4=[0]*4
for b in allreal:
    d4[gc.detect(b)[0]]+=1
print(f"  real blocks falling back to RAW (4-mode): {d4[3]}/{len(allreal)} = {100*d4[3]/len(allreal):.1f}%")
cap=sum(1 for b in allreal if gc.detect(b)[0]==3 and d16_words(b)<=N)
print(f"  of those, captured by a DELTA-16 mode:    {cap}/{d4[3]} = {100*cap/max(d4[3],1):.1f}%")
for nm,bs in R.items():
    print(f"    {nm:<12} 4-mode {agg(bs,A4):.3f}x -> +DELTA16 {agg(bs,A4D):.3f}x  ({100*(agg(bs,A4D)/agg(bs,A4)-1):+.1f}%)")

print()
print("="*86)
print("C) LEC bit- vs word-alignment accounting (fairness of the baseline table)")
print("="*86)
for nm,bs in R.items():
    bits=sum(32*0+ (lambda x: x)(0) for b in bs)
    lb=sum(math.ceil(sum([0])+ (lambda b: (lambda bits: bits)(0)) (b) ) for b in [])
    byt=0; wrd=0
    for b in bs:
        bits_b=32; prev=b[0]
        for w in b[1:]:
            d=w-prev; n=abs(d).bit_length()
            plen=2 if n==0 else (3 if n<=5 else n-2); bits_b+=plen+n; prev=w
        byt+=math.ceil(bits_b/8); wrd+=math.ceil(bits_b/32)*4
    inb=len(bs)*64
    print(f"  {nm:<12} LEC byte-aligned {inb/byt:.2f}x | word-aligned(32b) {inb/wrd:.2f}x   (paper must state which)")
