#!/usr/bin/env python3
# Verifies every numeric claim in paper_pacomp_v2.tex against the project data.
# Run:  python3 verify_paper_numbers.py
import sys, re, math, struct, zlib, random
sys.path.insert(0,"/sessions/brave-keen-faraday/mnt/32bit_RISCV")
import golden_compress as gc
N=gc.N; MASK=gc.MASK
tex=open("paper_pacomp_v2.tex",encoding="utf-8").read()
ok=[];bad=[]
def chk(label, claim, truth, tol=0.006):
    good = abs(claim-truth) <= tol*max(1,abs(truth)) or abs(claim-truth)<=0.005
    (ok if good else bad).append(f"{'PASS' if good else 'FAIL'}  {label}: paper={claim} data={truth:.4f}")

def blocks(p):
    w=gc.load_hex(p); return [w[i:i+N] for i in range(0,len(w)-N+1,N)]
R={n:blocks(f) for n,f in [("temperature","real_temp.hex"),("light","real_light.hex"),
                            ("voltage","real_volt.hex"),("mixed","real_mixed.hex")]}
FNS={0:gc.comp_zero_hw,1:gc.comp_rle_hw,2:gc.comp_delta_hw}
def rfix(bs,m): return len(bs)*N/sum(len(FNS[m](b)) for b in bs)
def radp(bs):
    o=0
    for b in bs:
        m=gc.detect(b)[0]; o+= len(FNS[m](b)) if m in FNS else N
    return len(bs)*N/o
allreal=[b for v in R.values() for b in v]

# --- Table tab:real ---
for nm,(z,r,d,a) in {"temperature":(0.94,0.70,2.28,2.31),"light":(0.99,1.92,2.23,3.15),
                     "voltage":(0.94,1.16,2.67,2.79),"mixed":(0.94,1.07,2.20,2.53)}.items():
    chk(f"tab:real {nm} ZERO",z,rfix(R[nm],0)); chk(f"tab:real {nm} RLE",r,rfix(R[nm],1))
    chk(f"tab:real {nm} DELTA",d,rfix(R[nm],2)); chk(f"tab:real {nm} ADAPT",a,radp(R[nm]))
chk("tab:real pooled ZERO",0.95,rfix(allreal,0)); chk("tab:real pooled RLE",1.07,rfix(allreal,1))
chk("tab:real pooled DELTA",2.33,rfix(allreal,2)); chk("tab:real pooled ADAPT",2.66,radp(allreal))
chk("abstract +14.3% over best-fixed",14.3,100*(radp(allreal)/rfix(allreal,2)-1),tol=0.02)

# --- Table tab:dist ---
d=[0]*4
for b in allreal: d[gc.detect(b)[0]]+=1
for i,(nm,claim) in enumerate([("ZERO",1.4),("RLE",22.0),("DELTA",72.3),("RAW",4.2)]):
    chk(f"tab:dist all-real {nm}%",claim,100*d[i]/len(allreal),tol=0.02)
for i,(nm,c) in enumerate([("ZERO",29),("RLE",451),("DELTA",1481),("RAW",87)]):
    chk(f"tab:dist count {nm}",c,d[i],tol=0)

# --- threshold policy ---
def dthr(b,t1=8,t2=8,wm=8):
    z=sum(1 for w in b if (w&MASK)==0); e=sum(1 for i in range(1,N) if (b[i]&MASK)==(b[i-1]&MASK))
    dw=0
    for i in range(1,N):
        dd=(b[i]-b[i-1])&MASK; s=(dd>>31)&1; w=1
        for k in range(31):
            if ((dd>>k)&1)!=s: w=k+2
        dw=max(dw,w)
    if z>=t1: return 0
    if e>=t2: return 1
    if dw<=wm: return 2
    return 3
def rthr(bs):
    o=0
    for b in bs:
        m=dthr(b); o+= len(FNS[m](b)) if m in FNS else N
    return len(bs)*N/o
chk("tab:policy ALL-REAL threshold",1.91,rthr(allreal))
chk("tab:policy ALL-REAL best-fixed",2.33,max(rfix(allreal,m) for m in (0,1,2)))
chk("tab:policy ALL-REAL exact",2.66,radp(allreal))
chk("17.9% worse than best-fixed",-17.9,100*(rthr(allreal)/max(rfix(allreal,m) for m in(0,1,2))-1),tol=0.02)
chk("+39.2% exact over threshold",39.2,100*(radp(allreal)/rthr(allreal)-1),tol=0.02)
tv=len(R["voltage"])
chk("voltage: threshold->RLE count",377,sum(1 for b in R['voltage'] if dthr(b)==1),tol=0)
chk("voltage: exact->DELTA count",463,sum(1 for b in R['voltage'] if gc.detect(b)[0]==2),tol=0)

# --- baselines ---
def lecb(b):
    bits=32;prev=b[0]
    for w in b[1:]:
        dd=w-prev;n=abs(dd).bit_length()
        bits+= (2 if n==0 else (3 if n<=5 else n-2))+n; prev=w
    return math.ceil(bits/8)
def lzwb(data):
    ds=256; t={bytes([i]):i for i in range(ds)}; w=b"";nc=0
    for c in data:
        wc=w+bytes([c])
        if wc in t: w=wc
        else:
            nc+=1
            if ds<4096: t[wc]=ds; ds+=1
            w=bytes([c])
    if w:nc+=1
    return math.ceil(nc*12/8)
import lz4.block as L4
for nm,(lzw,lz4v,z1,z6,lec,pac) in {"temperature":(1.39,1.46,2.12,2.30,5.36,2.31),
    "light":(1.81,2.83,4.06,4.45,6.20,3.15),"voltage":(1.75,2.40,3.66,4.15,6.54,2.79),
    "mixed":(1.62,2.05,3.02,3.31,5.86,2.53)}.items():
    bs=R[nm]; inb=len(bs)*64; a=b=c=e=f=0
    for blk in bs:
        data=struct.pack("<%dI"%N,*blk)
        a+=lzwb(data); b+=len(L4.compress(data,store_size=False))
        c+=len(zlib.compressobj(1,zlib.DEFLATED,-15).compress(data)+zlib.compressobj(1,zlib.DEFLATED,-15).flush()) if False else 0
        co=zlib.compressobj(1,zlib.DEFLATED,-15); c+=len(co.compress(data)+co.flush())
        co6=zlib.compressobj(6,zlib.DEFLATED,-15); e+=len(co6.compress(data)+co6.flush())
        f+=lecb(blk)
    chk(f"tab:base {nm} LZW",lzw,inb/a); chk(f"tab:base {nm} LZ4",lz4v,inb/b)
    chk(f"tab:base {nm} zlibL1",z1,inb/c); chk(f"tab:base {nm} zlibL6",z6,inb/e)
    chk(f"tab:base {nm} LEC",lec,inb/f)

# --- composability ---
def lecw(b):
    bits=32;prev=b[0]
    for w in b[1:]:
        dd=w-prev;n=abs(dd).bit_length()
        bits+=(2 if n==0 else (3 if n<=5 else n-2))+n;prev=w
    return math.ceil(bits/32)
def d16(b):
    for k in range(1,N):
        dd=(b[k]-b[k-1])&MASK; sd=dd-(1<<32) if dd>=(1<<31) else dd
        if not(-32768<=sd<=32767): return 99
    return 10
def LL(b): return {"ZERO":len(gc.comp_zero_hw(b)),"RLE":len(gc.comp_rle_hw(b)),
                   "DELTA":len(gc.comp_delta_hw(b)),"DELTA16":d16(b),"LEC":lecw(b),"RAW":N}
OD=["ZERO","RLE","DELTA","DELTA16","LEC","RAW"]
def sel(bs,allow):
    o=0
    for b in bs:
        l=LL(b); best=min((m for m in OD if m in allow), key=lambda m:(l[m],OD.index(m)))
        o+=l[best]
    return len(bs)*N/o
A4={"ZERO","RLE","DELTA","RAW"};A4D=A4|{"DELTA16"};A5=A4|{"LEC"}
chk("tab:compose real 4-mode",2.66,sel(allreal,A4)); chk("tab:compose real +D16",2.80,sel(allreal,A4D))
chk("tab:compose real +LEC",5.29,sel(allreal,A5))
chk("tab:compose real LEC-alone",5.27,len(allreal)*N/sum(lecw(b) for b in allreal))
chk("RAW blocks captured by DELTA16",87,sum(1 for b in allreal if gc.detect(b)[0]==3 and d16(b)<=N),tol=0)
print("\n".join(bad) if bad else "")
print(f"\n{'='*62}\nVERIFIED: {len(ok)} PASS, {len(bad)} FAIL\n{'='*62}")
