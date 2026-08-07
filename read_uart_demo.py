#!/usr/bin/env python3
# ===================================================================
# read_uart_demo.py -- v2: receives mode + out_len + FULL PAYLOAD per
# block (see asm_uart_demo.py) and checks every payload word against
# the golden reference model computed from uart_demo_src.hex, so the
# board read-back is now a bit-exact check, not just a mode/length
# check. Run this AFTER building/programming fpga_top_uart.v with the
# regenerated uart_demo.hex.
# ===================================================================
import sys
import os
import argparse

MODE_NAMES = {0: "ZERO", 1: "RLE", 2: "DELTA", 3: "RAW"}
N = 16
MASK = 0xFFFFFFFF


def load_hex(path):
    with open(path) as f:
        return [int(line.strip(), 16) & MASK for line in f if line.strip()]


def golden_expected(src_words, golden_path):
    """Import golden_compress from the project folder and recompute the
    expected (mode, comp_words) for every block of uart_demo_src.hex."""
    sys.path.insert(0, golden_path)
    import golden_compress as gc
    nblk = len(src_words) // N
    out = []
    for b in range(nblk):
        blk = src_words[b * N:(b + 1) * N]
        mode = gc.detect(blk)[0]
        if mode == 0:
            comp = gc.comp_zero_hw(blk)
        elif mode == 1:
            comp = gc.comp_rle_hw(blk)
        elif mode == 2:
            comp = gc.comp_delta_hw(blk)
        else:
            comp = blk[:]  # RAW: original block, no header
        out.append((mode, comp))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("port", help="COM port, e.g. COM5")
    ap.add_argument("--baud", type=int, default=115200)
    ap.add_argument("--nblk", type=int, default=14, help="number of blocks the board sends")
    ap.add_argument("--csv", default=None, help="write results to a CSV file (optional)")
    ap.add_argument("--project-dir", default=os.path.dirname(os.path.abspath(__file__)),
                     help="folder containing golden_compress.py and uart_demo_src.hex")
    args = ap.parse_args()

    try:
        import serial
    except ImportError:
        print("Missing pyserial. Run: pip install pyserial")
        sys.exit(1)

    src_path = os.path.join(args.project_dir, "uart_demo_src.hex")
    if not os.path.exists(src_path):
        print(f"[ERROR] {src_path} not found -- cannot compute golden expected output.")
        sys.exit(1)
    src_words = load_hex(src_path)
    expected = golden_expected(src_words, args.project_dir)

    print(f"Opening {args.port} @ {args.baud} baud (8N1)...")
    ser = serial.Serial(args.port, args.baud, timeout=30)
    ser.reset_input_buffer()

    print()
    print("=" * 70)
    print("  THE GATE IS OPEN. NOW PRESS THE RED CPU_RESET BUTTON ON THE BOARD!")
    print("  (The program on the board restarts automatically after a reset.)")
    print("  Streaming full payloads now (not just mode+length), so this run")
    print("  takes longer than the earlier mode-only demo -- several minutes")
    print("  for 14 blocks at 10 steps/second. This is expected.")
    print("=" * 70)

    rows = []
    total_in = 0
    total_out = 0
    n_mismatch = 0

    print(f"\n{'blk':<5}{'mode':<8}{'out_len':>9}{'ratio':>9}  payload check")
    print("-" * 60)

    for i in range(args.nblk):
        hdr = ser.read(2)
        if len(hdr) < 2:
            print(f"  [ERROR] block {i}: only received {len(hdr)}/2 header bytes.")
            print("        -> If nothing received: did you press CPU_RESET AFTER opening the script?")
            print("        -> If it received part then stopped: wait longer (30s read timeout),")
            print("           or the board already finished earlier -- press reset and rerun.")
            break
        mode, out_len = hdr[0], hdr[1]
        name = MODE_NAMES.get(mode, f"?({mode})")

        payload_raw = ser.read(4 * out_len)
        if len(payload_raw) < 4 * out_len:
            print(f"  [ERROR] block {i}: only received {len(payload_raw)}/{4*out_len} payload bytes.")
            break
        words = []
        for w in range(out_len):
            b0, b1, b2, b3 = payload_raw[4*w:4*w+4]
            words.append(b0 | (b1 << 8) | (b2 << 16) | (b3 << 24))

        exp_mode, exp_words = expected[i] if i < len(expected) else (None, None)
        ok_mode = (mode == exp_mode)
        ok_len = (out_len == len(exp_words)) if exp_words is not None else False
        ok_payload = (words == exp_words) if ok_len else False
        status = "OK, bit-exact" if (ok_mode and ok_payload) else "MISMATCH"
        if status == "MISMATCH":
            n_mismatch += 1

        ratio = N / out_len if out_len > 0 else float("inf")
        print(f"{i:<5}{name:<8}{out_len:>9}{ratio:>8.2f}x  {status}")
        if status == "MISMATCH":
            print(f"      got mode={mode} words={words}")
            print(f"      exp mode={exp_mode} words={exp_words}")

        rows.append((i, mode, name, out_len, ratio, status))
        total_in += N
        total_out += out_len

    ser.close()

    if rows:
        overall = total_in / total_out if total_out else float("inf")
        print("-" * 60)
        print(f"Total: {total_in} -> {total_out} words, adaptive ratio (REAL BOARD) = {overall:.3f}x")
        if n_mismatch == 0:
            print(f"[PASS] All {len(rows)} blocks bit-exact vs the reference model "
                  f"(mode, length, AND payload).")
        else:
            print(f"[FAIL] {n_mismatch}/{len(rows)} block(s) mismatched -- see detail above.")

    if args.csv and rows:
        with open(args.csv, "w", encoding="utf-8") as f:
            f.write("block,mode_code,mode_name,out_len,ratio,status\n")
            for r in rows:
                f.write(f"{r[0]},{r[1]},{r[2]},{r[3]},{r[4]:.4f},{r[5]}\n")
        print(f"Wrote {args.csv}")


if __name__ == "__main__":
    main()
