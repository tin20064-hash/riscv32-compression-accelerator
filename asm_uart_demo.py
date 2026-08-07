#!/usr/bin/env python3
# ===================================================================
# asm_uart_demo.py -- FULL-PAYLOAD UART demo (v2)
# -------------------------------------------------------------------
# Extends the original mode+out_len-only readout (which only proved
# selection and length matched the reference model) to stream the
# ACTUAL COMPRESSED BYTES of each block, closing the last gap in the
# silicon-verification chain (paper Section VII, "Validation on
# programmed silicon"): a bit-exact comparison against
# tb_expected_*_mixed.hex / the reference model is now possible from
# board read-back alone.
#
# Per block the board now sends, in order:
#   byte 0       : mode  (0=ZERO,1=RLE,2=DELTA,3=RAW)
#   byte 1       : out_len (words)
#   byte 2..     : out_len*4 payload bytes, one 32-bit compressed word
#                  at a time, LSB first (byte0,byte1,byte2,byte3 of
#                  word0, then word1, ...). For RAW blocks the payload
#                  is the 16 original words (no header), matching the
#                  format described in the paper.
#
# No RTL changes were needed: fpga_top_uart.v's mailbox already sends
# whatever byte the CPU stores to scratchpad word 255. This file only
# adds the payload-streaming loop after the existing mode/out_len send.
# ===================================================================
import os
from asm_riscv import assemble

PROGRAM = r"""
    addi x18, x0, 14          # NUM_BLK = 14
    addi x6, x0, 0            # i = 0
    lui  x20, 0x1              # x20 = 0x1000 (scratchpad byte base)
    addi x21, x20, 0x3FC      # x21 = 0x13FC (mailbox = word 255)
loop:
    slli x8, x6, 6             # i*64 (byte offset/block)
    add  x10, x20, x8          # src = 0x1000 + i*64
    pdetect x11, x10, x0
wait1:
    cstat x12
    srli  x13, x12, 30
    andi  x13, x13, 1
    beq   x13, x0, wait1
    andi  x14, x12, 3          # mode
    addi  x22, x0, 3
    beq   x14, x22, raw_case   # RAW (mode=3): CCOMPR does NOT support it, the dispatcher
                                # treats it as an error and never asserts done -> must
                                # skip it, report out_len=16 (not compressible)
    addi  x9, x20, 0x380       # dst = 0x1000 + 0x380 (word 224, reused)
    or    x15, x9, x14         # op_b = dst|mode
    ccompr x10, x15
wait2:
    cstat x16
    srli  x17, x16, 30
    andi  x17, x17, 1
    beq   x17, x0, wait2
    andi  x19, x16, 0x7FF      # out_len (words)
    add   x24, x9, x0          # payload word pointer = dst
    jal   x0, send_result
raw_case:
    addi  x19, x0, 16          # RAW: no compression, out_len = N = 16
    add   x24, x10, x0         # payload word pointer = src (RAW carries no header)
send_result:
    sw    x14, 0(x21)          # send the MODE byte over UART
    nop                        # IMPORTANT: create a mem_write=0 gap between
    nop                        # the 2 mailbox writes (2 back-to-back sw to the same addr
    nop                        # would not produce a separate rising edge without an
    nop                        # intervening non-write instruction) -- see fpga_top_uart.v
    sw    x19, 0(x21)          # send the OUT_LEN byte over UART
    nop
    nop
    nop
    nop
    # ---- stream out_len 32-bit words, 4 bytes each (LSB first) ----
    addi  x25, x0, 0           # word index j = 0
payload_words:
    beq   x25, x19, payload_done
    slli  x26, x25, 2
    add   x26, x26, x24        # addr of word j
    lw    x27, 0(x26)          # x27 = compressed word j
    sw    x27, 0(x21)          # byte0 (LSB)
    nop
    nop
    nop
    nop
    srli  x27, x27, 8
    sw    x27, 0(x21)          # byte1
    nop
    nop
    nop
    nop
    srli  x27, x27, 8
    sw    x27, 0(x21)          # byte2
    nop
    nop
    nop
    nop
    srli  x27, x27, 8
    sw    x27, 0(x21)          # byte3 (MSB)
    nop
    nop
    nop
    nop
    addi  x25, x25, 1
    jal   x0, payload_words
payload_done:
    addi  x6, x6, 1
    bne   x6, x18, loop
halt:
    jal   x0, halt
"""

if __name__ == "__main__":
    HERE = os.path.dirname(os.path.abspath(__file__))
    words = assemble(PROGRAM.splitlines())
    print(f"  instruction count: {len(words)}")
    if len(words) > 256:
        raise SystemExit(f"  !! program does not fit in 256-word imem "
                          f"({len(words)} words) -- shrink NUM_BLK or the loop body")
    while len(words) < 256:
        words.append(0)
    out = os.path.join(HERE, "uart_demo.hex")
    with open(out, "w") as f:
        for w in words:
            f.write(f"{w:08X}\n")
    print(f"  -> {out}")
