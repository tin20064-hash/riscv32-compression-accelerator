#!/usr/bin/env python3
import os
import random
from golden_compress import N, MASK, save_hex_1perline, detect, TAU1, TAU2, WMAX

HERE = os.path.dirname(os.path.abspath(__file__))
NUM_BLK = 128
SEED = 0xC0FFEE

def gen_zero_heavy(rng):
    blk = [0] * N
    k = rng.randint(1, 4)
    for pos in rng.sample(range(N), k):
        blk[pos] = rng.randint(1, 0xFFFFFFFF) & MASK
    return blk

def gen_repetitive(rng):
    nruns = rng.randint(2, 3)

    cuts = sorted(rng.sample(range(1, N), nruns - 1)) if nruns > 1 else []
    bounds = [0] + cuts + [N]
    blk = []
    prev = None
    for i in range(nruns):
        ln = bounds[i + 1] - bounds[i]
        v = rng.randint(0, 0xFFFFFFFF) & MASK
        while v == prev:
            v = rng.randint(0, 0xFFFFFFFF) & MASK
        prev = v
        blk += [v] * ln
    return blk[:N]

def gen_slow_varying(rng):
    base = rng.randint(0, 100000)
    blk = [base & MASK]
    for _ in range(N - 1):
        d = rng.randint(-8, 8)
        blk.append((blk[-1] + d) & MASK)
    return blk

GENS = [
    ("zero_heavy",   gen_zero_heavy),
    ("repetitive",   gen_repetitive),
    ("slow_varying", gen_slow_varying),
]
NAMES = ["ZERO", "RLE", "DELTA", "RAW"]

if __name__ == "__main__":
    print(f"Generate 3 datasets ({NUM_BLK} blocks/dataset, N={N}, seed=0x{SEED:X})\n")
    print(f"  {'dataset':<14}{'word':>8}{'mode detector chon (phan bo)':>40}")
    print(f"  {'-'*62}")
    for name, gen in GENS:
        rng = random.Random(SEED ^ hash(name) & 0xFFFFFFFF)
        words = []
        dist = [0, 0, 0, 0]
        for _ in range(NUM_BLK):
            blk = gen(rng)
            words += [w & MASK for w in blk]
            m = detect(blk, TAU1, TAU2, WMAX)[0]
            dist[m] += 1
        path = os.path.join(HERE, f"dataset_{name}.hex")
        save_hex_1perline(words, path)
        distr = " ".join(f"{NAMES[m]}={dist[m]}" for m in range(4) if dist[m])
        print(f"  {name:<14}{len(words):>8}    {distr}")
    print(f"\n  -> dataset_zero_heavy.hex / dataset_repetitive.hex / dataset_slow_varying.hex")
