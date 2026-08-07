#!/usr/bin/env python3
# ===================================================================
# asm_lec_baseline.py -- pure RV32I software cost of the LEC bit-length
# computation (Marcelloni & Vecchio 2008), for the SAME block used by
# the DELTA software baseline (asm_sw_baseline.py), so the two numbers
# are directly comparable: both run on cpu_top, both read demo_src.hex
# word 32..47 (the "block_delta" block from gen_demo.py).
#
# SCOPE, STATED HONESTLY: this program computes LEC's output LENGTH
# (the classification loop: diff -> abs -> bit-length -> prefix-code
# length -> running bit total), exactly mirroring golden_compress-style
# lec_bits()/lec_words() used throughout eval_baselines.py. It does NOT
# pack the variable-length codes into an output bitstream. That
# additional bit-packing pass is real work a deployed LEC encoder would
# also have to pay for and is NOT measured here, so the cycle count
# this program produces is a LOWER BOUND on the true software cost of
# running LEC -- the honest number is "at least this many cycles."
# See Section VI-F (Hardware against software) discussion in the paper.
# ===================================================================
import os
from asm_riscv import assemble

PROGRAM = r"""
    addi x18, x0, 16          # N = 16
    addi x30, x0, 1
    sw   x30, 1012(x0)        # marker 1: begin LEC length computation
    addi x5, x0, 128          # src byte 128 (word 32) = block_delta (same block DELTA uses)
    lw   x11, 0(x5)           # prev = w[0]
    addi x20, x0, 32          # bits_acc = 32 (base word, stored verbatim)
    addi x7, x0, 1            # i = 1
lloop:
    slli x10, x7, 2
    add  x10, x10, x5
    lw   x14, 0(x10)          # w[i]
    sub  x15, x14, x11        # d = w[i] - prev
    add  x11, x14, x0         # prev = w[i]
    bge  x15, x0, dpos        # if d >= 0, already non-negative
    sub  x15, x0, x15         # d = -d   (abs)
dpos:
    addi x16, x0, 0           # n = 0
    beq  x15, x0, ndone       # d == 0 -> n = 0 (skip the shift loop)
nloop:
    addi x16, x16, 1
    srli x15, x15, 1
    bne  x15, x0, nloop
ndone:
    addi x17, x0, 2           # plen default: n == 0 -> 2
    beq  x16, x0, plendone
    addi x19, x0, 6
    blt  x16, x19, plen3      # n <= 5 -> plen = 3
    addi x17, x16, -2         # else plen = n - 2
    jal  x0, plendone
plen3:
    addi x17, x0, 3
plendone:
    add  x21, x17, x16        # cost = plen + n
    add  x20, x20, x21        # bits_acc += cost
    addi x7, x7, 1
    bne  x7, x18, lloop
    addi x22, x20, 31         # bits_acc + 31
    srli x22, x22, 5          # out_len_words = ceil(bits_acc / 32)
    sw   x22, 1000(x0)        # word 250 = out_len LEC (words)
    sw   x20, 1004(x0)        # word 251 = total bits (diagnostic)
    addi x30, x0, 2
    sw   x30, 1012(x0)        # marker 2: LEC length computation done
halt:
    jal  x0, halt
"""

if __name__ == "__main__":
    HERE = os.path.dirname(os.path.abspath(__file__))
    words = assemble(PROGRAM.splitlines())
    print(f"  instruction count: {len(words)}")
    while len(words) < 256:
        words.append(0)
    out = os.path.join(HERE, "lec_baseline.hex")
    with open(out, "w") as f:
        for w in words:
            f.write(f"{w:08X}\n")
    print(f"  -> {out}")

    # Independent Python cross-check of the expected result, using the
    # same block gen_demo.py placed at word 32 of demo_src.hex.
    block_delta = [100]
    for d in (1, 2, 3, 1, 2, 3, 1, 2, 3, 1, 2, 3, 1, 2, 3):
        block_delta.append(block_delta[-1] + d)
    block_delta = block_delta[:16]

    def lec_bits(words):
        def cat(d):
            return abs(d).bit_length()
        def plen(n):
            if n == 0:
                return 2
            if n <= 5:
                return 3
            return n - 2
        bits = 32
        prev = words[0]
        for w in words[1:]:
            d = w - prev
            n = cat(d)
            bits += plen(n) + n
            prev = w
        return bits

    bits = lec_bits(block_delta)
    words_out = (bits + 31) // 32
    print(f"  expected: total bits = {bits}, out_len_words = {words_out}")
    print("  (tb_lec_baseline.v checks word 250 == this value before trusting the cycle count)")
