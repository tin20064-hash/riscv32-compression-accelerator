#!/usr/bin/env python3
import os, sys
from collections import defaultdict

N        = 16
MAX_BLK  = 512
HERE     = os.path.dirname(os.path.abspath(__file__))
DEFAULT  = os.path.join(HERE, "data.txt")  # tai Intel Lab Data ve, dat cung thu muc voi script nay (khop voi gen_real_datasets_full.py va .gitignore)

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
    return per_mote

def to_blocks(words, max_blk):
    blocks = []
    for i in range(0, len(words) - N + 1, N):
        blocks.append([w & 0xFFFFFFFF for w in words[i:i+N]])
        if len(blocks) >= max_blk:
            break
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
    per_mote = parse(src)

    motes = sorted(per_mote, key=lambda m: -len(per_mote[m]))[:8]
    print(f"  use the 8 motes with the most data: {motes}")

    temp_w, light_w, volt_w = [], [], []
    for m in motes:
        for (_, t, l, v) in per_mote[m]:
            temp_w.append(int(round(t * 100)))
            light_w.append(int(round(l)))
            volt_w.append(int(round(v * 100)))

    b_temp  = to_blocks(temp_w,  MAX_BLK)
    b_light = to_blocks(light_w, MAX_BLK)
    b_volt  = to_blocks(volt_w,  MAX_BLK)

    b_mixed, k = [], 0
    while len(b_mixed) < MAX_BLK and k < min(len(b_temp), len(b_light), len(b_volt)):
        b_mixed += [b_temp[k], b_light[k], b_volt[k]]
        k += 1
    b_mixed = b_mixed[:MAX_BLK]

    save_hex(b_temp,  os.path.join(HERE, "real_temp.hex"))
    save_hex(b_light, os.path.join(HERE, "real_light.hex"))
    save_hex(b_volt,  os.path.join(HERE, "real_volt.hex"))
    save_hex(b_mixed, os.path.join(HERE, "real_mixed.hex"))

    def stats(blocks, name):
        zeros = runs = 0; total = 0
        for b in blocks:
            zeros += sum(1 for w in b if w == 0)
            runs  += sum(1 for i in range(1, N) if b[i] == b[i-1])
            total += N
        print(f"  {name:<11} zero={100.0*zeros/total:5.1f}%  run-pairs={100.0*runs/(total-total//N):5.1f}%")
    print("\n  Real characteristics (verifying the assumption):")
    stats(b_temp,  "real_temp")
    stats(b_light, "real_light")
    stats(b_volt,  "real_volt")
    stats(b_mixed, "real_mixed")

if __name__ == "__main__":
    main()
