#!/usr/bin/env python3
# ===================================================================
# asm_uart_demo.py -- UART demo: streams (mode, out_len) per block
# -------------------------------------------------------------------
# LUU Y (sua ngay 09/08/2026): ban truoc day cua file nay co them 1
# vong lap "payload_words" dung `lw` doc lai tu scratchpad de gui ca
# du lieu nen thuc su qua UART. Da BO doan do vi 2 ly do:
#
#   1. Bai bao (RV_PC_final.tex) chi claim/verify (mode, out_len) qua
#      UART (Sec. Verification Results: "every (mode, out_len) pair
#      streamed over UART matched the golden-model prediction exactly"),
#      KHONG claim gui/doi chieu payload qua UART.
#   2. Bai bao tu liet ke "a scratchpad load path" la FUTURE WORK
#      (Sec. Conclusion) -- tuc CPU doc lai (`lw`) tu scratchpad la
#      duong chua duoc xay/chua duoc verify. Thuc te dung thu: mem_stage.v
#      chi co RAM noi bo rieng cho load/store thuong, khong co duong noi
#      nao cho CPU `lw` doc dung tu scratchpad that (spad_raddr/spad_rdata
#      chi noi cho accelerator dung noi bo) -- nen `lw` tra ve toan 0.
#      Ket qua: payload gui qua UART sai hoan toan (chi mode/out_len la
#      dung, vi 2 gia tri do lay tu thanh ghi/cstat, khong qua `lw`).
#
# Quay lai dung dung pham vi bai bao da verify: moi block chi gui 2
# byte (mode, out_len), khop voi tb_fpga_top_uart.v da commit tu dau.
# Neu sau nay muon lam duong doc scratchpad that su cho CPU (future
# work), can them 1 cong doc thu 2 vao scratchpad.v roi moi bat lai
# tinh nang gui payload.
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
    jal   x0, send_result
raw_case:
    addi  x19, x0, 16          # RAW: no compression, out_len = N = 16
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
