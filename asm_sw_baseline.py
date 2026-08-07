#!/usr/bin/env python3
import os
from asm_riscv import assemble

PROGRAM = r"""
    # ---- init ----
    addi x18, x0, 16          # N = 16

    # ================= ZERO compress (block0) =================
    addi x30, x0, 1
    sw   x30, 1012(x0)        # marker 1: begin ZERO
    addi x5, x0, 0            # src byte 0   (word 0)
    addi x6, x0, 256          # dst byte 256 (word 64)
    addi x7, x0, 0            # i = 0
    addi x8, x0, 0            # bitmap = 0
    addi x9, x6, 4            # payload ptr (slot 0 = header)
zloop:
    slli x10, x7, 2
    add  x10, x10, x5
    lw   x11, 0(x10)          # w = src[i]
    beq  x11, x0, zskip
    addi x12, x0, 1
    sll  x12, x12, x7
    or   x8, x8, x12          # bitmap |= 1<<i
    sw   x11, 0(x9)           # payload
    addi x9, x9, 4
zskip:
    addi x7, x7, 1
    bne  x7, x18, zloop
    sw   x8, 0(x6)            # header = (0<<16)|bitmap
    sub  x13, x9, x6
    srli x13, x13, 2
    sw   x13, 1000(x0)        # word 250 = out_len ZERO
    addi x30, x0, 2
    sw   x30, 1012(x0)        # marker 2: ZERO done

    # ================= RLE compress (block1) =================
    addi x30, x0, 3
    sw   x30, 1012(x0)        # marker 3: begin RLE
    addi x5, x0, 64           # src byte 64  (word 16)
    addi x6, x0, 384          # dst byte 384 (word 96)
    addi x9, x6, 4
    lw   x11, 0(x5)           # run_val = w0
    addi x12, x0, 1           # run_cnt = 1
    addi x13, x0, 0           # num_runs = 0
    addi x7, x0, 1            # i = 1
rloop:
    slli x10, x7, 2
    add  x10, x10, x5
    lw   x14, 0(x10)
    beq  x14, x11, rsame
    sw   x11, 0(x9)           # flush (val, cnt)
    addi x9, x9, 4
    sw   x12, 0(x9)
    addi x9, x9, 4
    addi x13, x13, 1
    add  x11, x14, x0
    addi x12, x0, 1
    jal  x0, rnext
rsame:
    addi x12, x12, 1
rnext:
    addi x7, x7, 1
    bne  x7, x18, rloop
    sw   x11, 0(x9)           # flush last run
    addi x9, x9, 4
    sw   x12, 0(x9)
    addi x9, x9, 4
    addi x13, x13, 1
    lui  x14, 0x10            # mode RLE = 1<<16
    or   x14, x14, x13
    sw   x14, 0(x6)           # header
    sub  x15, x9, x6
    srli x15, x15, 2
    sw   x15, 1004(x0)        # word 251 = out_len RLE
    addi x30, x0, 4
    sw   x30, 1012(x0)        # marker 4: RLE done

    # ================= DELTA compress (block2) =================
    addi x30, x0, 5
    sw   x30, 1012(x0)        # marker 5: begin DELTA
    addi x5, x0, 128          # src byte 128 (word 32)
    addi x6, x0, 512          # dst byte 512 (word 128)
    # --- pass 1: check every diff is in [-128,127] ---
    lw   x11, 0(x5)           # prev = w0
    addi x7, x0, 1
dchk:
    slli x10, x7, 2
    add  x10, x10, x5
    lw   x14, 0(x10)
    sub  x15, x14, x11
    addi x16, x15, 128
    sltiu x16, x16, 256       # 1 if d+128 < 256 (unsigned)
    beq  x16, x0, draw
    add  x11, x14, x0
    addi x7, x7, 1
    bne  x7, x18, dchk
    # --- packed: header + base + 4 packed words ---
    lui  x14, 0x20            # mode DELTA = 2<<16
    ori  x14, x14, 0x100      # bit8 = packed
    sw   x14, 0(x6)
    lw   x11, 0(x5)
    sw   x11, 4(x6)           # base = w0
    addi x7, x0, 1            # diff idx i = 1
    addi x9, x6, 8            # dst ptr = word 2
packw:
    addi x16, x0, 0           # acc = 0
    addi x17, x0, 0           # shift = 0
packb:
    addi x19, x0, 16
    bge  x7, x19, pzero       # i >= 16 -> pad 0
    slli x10, x7, 2
    add  x10, x10, x5
    lw   x14, 0(x10)
    sub  x15, x14, x11
    add  x11, x14, x0
    jal  x0, pmask
pzero:
    addi x15, x0, 0
pmask:
    andi x15, x15, 0xFF
    sll  x15, x15, x17
    or   x16, x16, x15
    addi x17, x17, 8
    addi x7, x7, 1
    addi x19, x0, 32
    bne  x17, x19, packb
    sw   x16, 0(x9)
    addi x9, x9, 4
    addi x19, x0, 17
    bne  x7, x19, packw
    addi x14, x0, 6
    sw   x14, 1008(x0)        # word 252 = out_len DELTA = 6
    jal  x0, ddone
draw:
    # raw fallback: header + 16 original words (demo block fits -> this path not taken)
    lui  x14, 0x20
    sw   x14, 0(x6)
    addi x7, x0, 0
drl:
    slli x10, x7, 2
    add  x10, x10, x5
    lw   x14, 0(x10)
    slli x10, x7, 2
    addi x10, x10, 4
    add  x10, x10, x6
    sw   x14, 0(x10)
    addi x7, x7, 1
    bne  x7, x18, drl
    addi x14, x0, 17
    sw   x14, 1008(x0)
ddone:
    addi x30, x0, 6
    sw   x30, 1012(x0)        # marker 6: DELTA done
halt:
    jal  x0, halt
"""

if __name__ == "__main__":
    HERE = os.path.dirname(os.path.abspath(__file__))
    words = assemble(PROGRAM.splitlines())
    print(f"  instruction count: {len(words)}")
    while len(words) < 256:
        words.append(0)
    out = os.path.join(HERE, "sw_baseline.hex")
    with open(out, "w") as f:
        for w in words:
            f.write(f"{w:08X}\n")
    print(f"  -> {out}")
