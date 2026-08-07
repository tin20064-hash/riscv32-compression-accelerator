// ===================================================================
// compress_api.h -- Phase 3.1: C wrapper for the custom instructions
// -------------------------------------------------------------------
// Map sang 3 custom instruction (opcode 0x0B = custom-0):
//   PDETECT funct3=000 : detect the pattern of one block
//   CCOMPR  funct3=001 : compress one block in a given mode
//   CSTAT   funct3=010 : read status (poll done + result)
//
// Custom la R-type: rd, rs1=op_a, rs2=op_b, funct7=0.
// Since CCOMPR/PDETECT take many cycles and the pipeline does not stall on the accel,
//   the result is read via CSTAT (poll the done bit) -- see accel_wait().
//
// Status word (compress_accel.v):
//   [31]=busy [30]=done [29]=err [28]=last_op [27:0]=last_result
//   last_op=0 -> last_result = out_len (compressed word count)
//   last_op=1 -> last_result = det_word
// det_word:
//   [1:0]=mode  [7:2]=zero_cnt  [13:8]=run_cnt  [21:16]=delta_w
// ===================================================================
#ifndef COMPRESS_API_H
#define COMPRESS_API_H
#include <stdint.h>

#define MODE_ZERO   0u
#define MODE_RLE    1u
#define MODE_DELTA  2u
#define MODE_RAW    3u

#define CSTAT_BUSY(s)    (((s) >> 31) & 1u)
#define CSTAT_DONE(s)    (((s) >> 30) & 1u)
#define CSTAT_ERR(s)     (((s) >> 29) & 1u)
#define CSTAT_LASTOP(s)  (((s) >> 28) & 1u)
#define CSTAT_RESULT(s)  ((s) & 0x0FFFFFFFu)

#define DET_MODE(r)      ((r) & 0x3u)
#define DET_ZEROCNT(r)   (((r) >> 2)  & 0x3Fu)
#define DET_RUNCNT(r)    (((r) >> 8)  & 0x3Fu)
#define DET_DELTAW(r)    (((r) >> 16) & 0x3Fu)

// Read status once.
static inline uint32_t accel_cstat(void) {
    uint32_t s;
    asm volatile (".insn r 0x0B, 2, 0, %0, x0, x0" : "=r"(s));
    return s;
}

// Wait until the accel asserts done; return the final status word.
static inline uint32_t accel_wait(void) {
    uint32_t s;
    do { s = accel_cstat(); } while (!CSTAT_DONE(s));
    return s;
}

// Detect the pattern of one block.
//   src = scratchpad byte address of the block.
//   thr = packed thresholds {tau1[5:0], tau2[13:8], wmax[21:16]}; thr=0 -> default.
// Returns det_word (use DET_MODE / DET_* to unpack).
static inline uint32_t detect_pattern(uint32_t src, uint32_t thr) {
    uint32_t d;
    asm volatile (".insn r 0x0B, 0, 0, %0, %1, %2" : "=r"(d) : "r"(src), "r"(thr));
    (void)d;                               // the direct result may be stale
    return CSTAT_RESULT(accel_wait());     // = det_word
}

// Compress one block.
//   src       = source block byte address.
//   dest_mode = (dest byte address) | mode   (mode in the low 2 bits, dest word-aligned).
// Returns out_len (words written to the dest region).
static inline uint32_t compress_block(uint32_t src, uint32_t dest_mode) {
    asm volatile (".insn r 0x0B, 1, 0, x0, %0, %1" :: "r"(src), "r"(dest_mode));
    return CSTAT_RESULT(accel_wait());     // = out_len
}

// Helper to call a single mode directly (to force a mode instead of detect).
#define compress_zero(src, dest)   compress_block((src), ((dest) | MODE_ZERO))
#define compress_rle(src, dest)    compress_block((src), ((dest) | MODE_RLE))
#define compress_delta(src, dest)  compress_block((src), ((dest) | MODE_DELTA))

#endif // COMPRESS_API_H
