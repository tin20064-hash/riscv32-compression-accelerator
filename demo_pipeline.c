// ===================================================================
// demo_pipeline.c -- Phase 3.2: runtime detect -> select -> compress loop
// -------------------------------------------------------------------
// End-to-end scenario (the paper's main figure):
//   - Source data already sits in the scratchpad (the CPU preloads it via store,
//     hoac testbench preload).
//   - For each block: detect_pattern() gets the mode -> compress_block() uses
//     that exact mode -> dest pointer advances by out_len.
//   - mode[] is kept to observe the detector picking modes by data characteristics.
//
// Compile (can RISC-V GCC + crt0.S + link.ld, xem Makefile):
//   make demo_pipeline.hex
// (tuong duong: gcc -march=rv32i -mabi=ilp32 -nostdlib -ffreestanding -O2
//   -mno-relax -T link.ld crt0.S demo_pipeline.c -o demo_pipeline.elf
//   roi objcopy -O verilog demo_pipeline.elf demo_pipeline.hex)
//
// Khong co toolchain: dung asm_riscv.py (assembler toi gian) de tu build
//   demo_pipeline.hex tu 1 chuong trinh assembly tuong duong -> chay ModelSim.
//
// Diem vao that su la _start trong crt0.S (gan sp + xoa .bss truoc), roi
// crt0.S moi goi vao c_entry() duoi day -- xem crt0.S de biet ly do.
// ===================================================================
#include "compress_api.h"

#define SPAD_BYTE_BASE 0x1000u          // bit[12]=1 -> vung scratchpad
#define N              16               // word / block
#define BLOCK_BYTES    (N * 4)
#define NUM_BLK        3                // demo: 3 blocks with different characteristics

// Source region: block i at word i*N ; dest region: starts right after source.
#define SRC0_BYTE      (SPAD_BYTE_BASE + 0)
#define DST0_WORD      (NUM_BLK * N)
#define DST0_BYTE      (SPAD_BYTE_BASE + DST0_WORD * 4)

uint32_t mode_log[NUM_BLK];             // detector-selected mode (for checking)
uint32_t len_log[NUM_BLK];              // out_len tung block

void run_pipeline(void) {
    uint32_t dst = DST0_BYTE;           // dest pointer (byte)
    for (uint32_t i = 0; i < NUM_BLK; i++) {
        uint32_t src = SRC0_BYTE + i * BLOCK_BYTES;

        // 1) detect: pick the mode by data pattern (thr=0 -> default thresholds)
        uint32_t det  = detect_pattern(src, 0);
        uint32_t mode = DET_MODE(det);
        mode_log[i]   = mode;

        // 2) compress using the just-selected mode
        uint32_t out_len = compress_block(src, dst | mode);
        len_log[i]       = out_len;

        // 3) advance the dest pointer by the compressed word count
        dst += out_len * 4;
    }
}

// Goi boi crt0.S sau khi sp da duoc gan va .bss da duoc xoa ve 0 --
// KHONG dat ten la _start o day, vi _start (dia chi 0x0, diem CPU
// fetch dau tien sau reset) phai la lenh assembly thuan trong crt0.S.
void c_entry(void) {
    run_pipeline();
    for (;;) { }                        // halt
}
