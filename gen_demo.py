#!/usr/bin/env python3
import os
from golden_compress import (comp_zero_hw, comp_rle_hw, comp_delta_hw,
                             detect, save_hex_1perline, TAU1, TAU2, WMAX, N)

HERE = os.path.dirname(os.path.abspath(__file__))

block_zero = [0]*16
for i in (2, 7, 11, 14):
    block_zero[i] = 0xA0000000 + i
block_rle = [5]*9 + [7]*7
block_delta = [100]
for d in (1, 2, 3, 1, 2, 3, 1, 2, 3, 1, 2, 3, 1, 2, 3):
    block_delta.append(block_delta[-1] + d)
block_delta = block_delta[:16]

blocks = [block_zero, block_rle, block_delta]
comp_fns = {0: comp_zero_hw, 1: comp_rle_hw, 2: comp_delta_hw}
names = ["ZERO", "RLE", "DELTA", "RAW"]

src = []
for b in blocks:
    src += [w & 0xFFFFFFFF for w in b]
save_hex_1perline(src, os.path.join(HERE, "demo_src.hex"))

dest = []
DST0_WORD = len(blocks) * N
lines = []
print(f"Thresholds: tau1={TAU1} tau2={TAU2} wmax={WMAX}\n")
print(f"  {'blk':<4}{'mode':<8}{'out_len':>8}{'dst_word':>10}")
off = DST0_WORD
for i, b in enumerate(blocks):
    mode = detect(b, TAU1, TAU2, WMAX)[0]
    comp = comp_fns[mode](b)
    print(f"  {i:<4}{names[mode]:<8}{len(comp):>8}{off:>10}")
    lines.append(f"{i} {mode} {len(comp)} {off}")
    dest += comp
    off += len(comp)

save_hex_1perline(dest, os.path.join(HERE, "demo_expected_dest.hex"))
with open(os.path.join(HERE, "demo_expected.txt"), "w") as f:
    f.write("# blk mode out_len dst_word\n")
    f.write("\n".join(lines) + "\n")

print(f"\n  demo_src.hex          : {len(src)} word")
print(f"  demo_expected_dest.hex: {len(dest)} words (dest word {DST0_WORD}..{DST0_WORD+len(dest)-1})")
print(f"  Expected modes         : {[detect(b, TAU1, TAU2, WMAX)[0] for b in blocks]}  (= [ZERO,RLE,DELTA])")
