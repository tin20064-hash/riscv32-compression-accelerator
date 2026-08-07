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
// Compile (on a machine with RISC-V GCC):
//   riscv32-unknown-elf-gcc -march=rv32i -mabi=ilp32 -nostdlib -O2 \
//       -T link.ld demo_pipeline.c -o demo_pipeline.elf
//   riscv32-unknown-elf-objcopy -O verilog demo_pipeline.elf demo_pipeline.hex
//
// Without a toolchain: use asm_riscv.py (minimal assembler) to build
//   demo_pipeline.hex from an equivalent assembly program -> run in ModelSim.
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

void _start(void) {
    run_pipeline();
    for (;;) { }                        // halt
}
