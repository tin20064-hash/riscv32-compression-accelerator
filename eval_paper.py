#!/usr/bin/env python3
import os, random
from golden_compress import (
    comp_zero_hw, comp_rle_hw, comp_delta_hw,
    decompress, detect, N, MASK,
)

HERE = os.path.dirname(os.path.abspath(__file__))
NB   = 128                      

FNS  = {0: comp_zero_hw, 1: comp_rle_hw, 2: comp_delta_hw}
MODE_NAMES = ["ZERO", "RLE", "DELTA", "RAW"]

def detect_threshold(block, tau1=8, tau2=8, wmax=8):
    zero_cnt = sum(1 for w in block if (w & MASK) == 0)
    run_cnt  = sum(1 for i in range(1, N) if (block[i] & MASK) == (block[i-1] & MASK))
    delta_w  = 0
    for i in range(1, N):
        d = (block[i] - block[i-1]) & MASK
        s = (d >> 31) & 1
        w = 1
        for k in range(31):
            if ((d >> k) & 1) != s:
                w = k + 2
        if w > delta_w:
            delta_w = w
    if zero_cnt >= tau1:   return 0
    if run_cnt  >= tau2:   return 1
    if delta_w  <= wmax:   return 2
    return 3

def ds_zero_heavy(n, rng):
    out = []
    for _ in range(n):
        b = [0]*N
        for p in rng.sample(range(N), rng.randint(1, 4)):
            b[p] = rng.randint(1, MASK)
        out.append(b)
    return out

def ds_repetitive(n, rng):
    out = []
    for _ in range(n):
        nr = rng.randint(2, 4); b = []
        for _ in range(nr):
            b += [rng.randint(0, MASK)] * (N // nr)
        out.append((b + [b[-1]]*N)[:N])
    return out

def ds_slow(n, rng):
    out = []
    for _ in range(n):
        b = [rng.randint(0, 100000)]
        for _ in range(N-1):
            b.append((b[-1] + rng.randint(-8, 8)) & MASK)
        out.append(b)
    return out

def ds_random(n, rng):
    return [[rng.randint(0, MASK) for _ in range(N)] for _ in range(n)]

def ds_mixed(n, rng):
    gens = [ds_zero_heavy, ds_repetitive, ds_slow, ds_random]
    out = []
    while len(out) < n:
        for g in gens:
            out += g(1, rng)
    return out[:n]

def load_hex_blocks(path):
    words = []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if line:
                words.append(int(line, 16))
    return [words[i:i+N] for i in range(0, len(words) - N + 1, N)]

def ratio_fixed(blocks, m):
    out = sum(len(FNS[m](b)) for b in blocks)
    return len(blocks)*N / out

def ratio_adapt(blocks):
    out = 0
    for b in blocks:
        m = detect(b)[0]
        out += len(FNS[m](b)) if m in FNS else N
    return len(blocks)*N / out

def ratio_adapt_threshold(blocks):
    out = 0
    for b in blocks:
        m = detect_threshold(b)
        out += len(FNS[m](b)) if m in FNS else N
    return len(blocks)*N / out

def mode_dist(blocks):
    d = [0]*4
    for b in blocks:
        d[detect(b)[0]] += 1
    return d

def lossless_fail(blocks):
    bad = 0
    for b in blocks:
        m = detect(b)[0]
        if m in FNS and decompress(FNS[m](b)) != b:
            bad += 1
    return bad

def main():
    rng = random.Random(0xC0FFEE)
    synth = {
        "zero_heavy": ds_zero_heavy(NB, rng),
        "repetitive": ds_repetitive(NB, rng),
        "slow_vary":  ds_slow(NB, rng),
        "random":     ds_random(NB, rng),
        "synth_mixed": ds_mixed(NB, rng),
    }
    real = {}
    for name in ["real_temp", "real_light", "real_volt", "real_mixed"]:
        p = os.path.join(HERE, name + ".hex")
        if os.path.exists(p):
            real[name] = load_hex_blocks(p)

    lines = []
    def emit(s=""):
        print(s); lines.append(s)

    emit("=" * 70)
    emit(" EVAL PAPER -- PA-COMP  (synthetic + REAL Intel Berkeley Lab)")
    emit(f" mode-selection policy: EXACT-COST (no threshold); N={N} words/block")
    emit("=" * 70)

    for title, group in [("A. SYNTHETIC DATASET (seed 0xC0FFEE)", synth),
                         ("B. REAL DATASET (Intel Lab, 2.3M records, 8 motes)", real)]:
        emit(f"\n[{title}]")
        emit(f"  {'dataset':<12}{'nblk':>6}{'ZERO':>7}{'RLE':>7}{'DELTA':>7}{'ADAPT':>8}   mode-dist Z/R/D/RAW")
        emit("  " + "-"*72)
        for name, blocks in group.items():
            rz, rr, rd = (ratio_fixed(blocks, m) for m in (0, 1, 2))
            ra = ratio_adapt(blocks)
            d  = mode_dist(blocks)
            emit(f"  {name:<12}{len(blocks):>6}{rz:>7.2f}{rr:>7.2f}{rd:>7.2f}{ra:>8.2f}   "
                 f"{d[0]}/{d[1]}/{d[2]}/{d[3]}")
        allb = [b for blks in group.values() for b in blks]
        if allb:
            rz, rr, rd = (ratio_fixed(allb, m) for m in (0, 1, 2))
            ra = ratio_adapt(allb)
            best = max(rz, rr, rd)
            bestn = ["ZERO","RLE","DELTA"][[rz,rr,rd].index(best)]
            emit("  " + "-"*72)
            emit(f"  {'OVERALL':<12}{len(allb):>6}{rz:>7.2f}{rr:>7.2f}{rd:>7.2f}{ra:>8.2f}")
            emit(f"  -> best-fixed = {bestn} {best:.3f}x ; ADAPTIVE = {ra:.3f}x ; "
                 f"improvement = +{(ra/best-1)*100:.1f}%")

    emit("\n[C. ROUND-TRIP LOSSLESS decompress(compress(x))==x]")
    total = fails = 0
    for name, blocks in {**synth, **real}.items():
        f = lossless_fail(blocks)
        total += len(blocks); fails += f
        emit(f"  {name:<12}{len(blocks):>6} block  FAIL={f}")
    emit(f"  TOTAL: {total} block, FAIL={fails}  ({'100% PASS' if fails==0 else 'CO LOI'})")

    emit("\n[D. MODE-SELECTION POLICY: priority-threshold (tau=8) vs EXACT-COST]")
    emit("  Reason for the design change: the threshold, calibrated on synthetic data,")
    emit("  does NOT transfer to real data; exact-cost is per-block optimal,")
    emit("  parameter-free, adding only three 6-bit length calcs + a min mux.")
    emit(f"  {'dataset':<12}{'best-fixed':>11}{'thresh(8)':>11}{'EXACT-COST':>12}")
    emit("  " + "-"*48)
    csv = ["dataset,best_fixed,threshold8,exact_cost"]
    for name, blocks in {**synth, **real}.items():
        bf = max(ratio_fixed(blocks, m) for m in (0, 1, 2))
        rt = ratio_adapt_threshold(blocks)
        rc = ratio_adapt(blocks)
        emit(f"  {name:<12}{bf:>11.2f}{rt:>11.2f}{rc:>12.2f}")
        csv.append(f"{name},{bf:.4f},{rt:.4f},{rc:.4f}")
    allb = [b for blks in {**synth, **real}.values() for b in blks]
    bf = max(ratio_fixed(allb, m) for m in (0, 1, 2))
    rt = ratio_adapt_threshold(allb)
    rc = ratio_adapt(allb)
    emit("  " + "-"*48)
    emit(f"  {'ALL':<12}{bf:>11.2f}{rt:>11.2f}{rc:>12.2f}")
    emit(f"  -> EXACT-COST vs best-fixed: +{(rc/bf-1)*100:.1f}% ; "
         f"vs threshold-policy: +{(rc/rt-1)*100:.1f}%")
    csv.append(f"ALL,{bf:.4f},{rt:.4f},{rc:.4f}")

    with open(os.path.join(HERE, "eval_paper_results.md"), "w", encoding="utf-8") as f:
        f.write("# eval_paper.py results (single source of numbers for the paper)\n\n```\n")
        f.write("\n".join(lines))
        f.write("\n```\n")
    with open(os.path.join(HERE, "eval_paper_policy.csv"), "w") as f:
        f.write("\n".join(csv))
    print("\n  -> wrote eval_paper_results.md + eval_paper_policy.csv")

if __name__ == "__main__":
    main()
