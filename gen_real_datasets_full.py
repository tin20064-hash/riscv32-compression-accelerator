#!/usr/bin/env python3
# ===================================================================
# gen_real_datasets_full.py -- FULL-CORPUS variant of gen_real_datasets.py
# -------------------------------------------------------------------
# Same parsing, same filtering, same 8-motes-with-most-data selection
# as gen_real_datasets.py (methodology unchanged), but with the 512-
# block-per-channel cap REMOVED: every available block from those 8
# motes is kept. Writes to *_full.hex (does not overwrite the original
# 512-block real_*.hex files, so the existing paper numbers stay
# reproducible until a decision is made to adopt the full-corpus ones).
# ===================================================================
import os, sys
from collections import defaultdict

N    = 16
HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT = os.path.join(HERE, "data.txt")

def parse(path):
    per_mote = defaultdict(list)
    kept = dropped = 0
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            p = line.split()
            if len(p) != 8:
                dropped += 1
                continue
            try:
                epoch  = int(p[2]); mote = int(p[3])
                temp   = float(p[4]); light = float(p[6]); volt = float(p[7])
            except ValueError:
                dropped += 1
                continue
            if not (0.0 < temp < 50.0 and 0.0 <= light <= 2000.0 and 2.0 < volt < 3.5):
                dropped += 1
                continue
            per_mote[mote].append((epoch, temp, light, volt))
            kept += 1
    for m in per_mote:
        per_mote[m].sort()
    print(f"  read done: kept {kept} / dropped {dropped} corrupt records, {len(per_mote)} motes")
    return per_mote, kept, dropped

def to_blocks(words):
    blocks = []
    for i in range(0, len(words) - N + 1, N):
        blocks.append([w & 0xFFFFFFFF for w in words[i:i+N]])
    return blocks

def save_hex(blocks, path):
    with open(path, "w") as f:
        for b in blocks:
            for w in b:
                f.write(f"{w:08X}\n")
    print(f"  -> {os.path.basename(path)}: {len(blocks)} block ({len(blocks)*N} word)")

def main():
    src = sys.argv[1] if len(sys.argv) > 1 else DEFAULT
    print(f"Source: {src}")
    per_mote, kept, dropped = parse(src)

    motes = sorted(per_mote, key=lambda m: -len(per_mote[m]))[:8]
    print(f"  use the 8 motes with the most data: {motes}")
    for m in motes:
        print(f"    mote {m}: {len(per_mote[m])} valid readings")

    temp_w, light_w, volt_w = [], [], []
    for m in motes:
        for (_, t, l, v) in per_mote[m]:
            temp_w.append(int(round(t * 100)))
            light_w.append(int(round(l)))
            volt_w.append(int(round(v * 100)))

    b_temp  = to_blocks(temp_w)
    b_light = to_blocks(light_w)
    b_volt  = to_blocks(volt_w)

    b_mixed, k = [], 0
    while k < min(len(b_temp), len(b_light), len(b_volt)):
        b_mixed += [b_temp[k], b_light[k], b_volt[k]]
        k += 1

    save_hex(b_temp,  os.path.join(HERE, "real_temp_full.hex"))
    save_hex(b_light, os.path.join(HERE, "real_light_full.hex"))
    save_hex(b_volt,  os.path.join(HERE, "real_volt_full.hex"))
    save_hex(b_mixed, os.path.join(HERE, "real_mixed_full.hex"))

    total_blocks = len(b_temp) + len(b_light) + len(b_volt) + len(b_mixed)
    print(f"\n  TOTAL full-corpus blocks: {total_blocks} "
          f"(vs. 2048 in the 512-per-channel sample used in the paper)")
    print(f"  Coverage: {kept} filtered records available, "
          f"{(len(b_temp)+len(b_light)+len(b_volt))*N} words consumed across the 3 base channels")

if __name__ == "__main__":
    main()
