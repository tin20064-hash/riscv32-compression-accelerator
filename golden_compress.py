#!/usr/bin/env python3

import os

N = 16
MASK = 0xFFFFFFFF

def comp_zero_hw(block):
    assert len(block) == N
    bitmap = 0
    payload = []
    for i, w in enumerate(block):
        if w != 0:
            bitmap |= (1 << i)
            payload.append(w & MASK)
    header = (0 << 16) | (bitmap & 0xFFFF)
    return [header] + payload

def comp_rle_hw(block):
    assert len(block) == N
    runs = []
    run_val = block[0] & MASK
    run_cnt = 1
    for w in block[1:]:
        w &= MASK
        if w == run_val:
            run_cnt += 1
        else:
            runs.append((run_val, run_cnt))
            run_val, run_cnt = w, 1
    runs.append((run_val, run_cnt))
    header = (1 << 16) | (len(runs) & 0xFFFF)
    out = [header]
    for v, c in runs:
        out += [v & MASK, c & MASK]
    return out

def comp_delta_hw(block):
    assert len(block) == N
    diffs = []
    fits = True
    for k in range(1, N):
        d = (block[k] - block[k - 1]) & MASK          
        sd = d - (1 << 32) if d >= (1 << 31) else d   
        if not (-128 <= sd <= 127):
            fits = False
        diffs.append(d)
    if fits:
        header = (2 << 16) | (1 << 8)
        base = block[0] & MASK
        db = [d & 0xFF for d in diffs]
        pw = []
        for j in range(4):
            w = 0
            for b in range(4):
                idx = j * 4 + b
                if idx < len(db):
                    w |= db[idx] << (8 * b)
            pw.append(w & MASK)
        return [header, base] + pw                     
    else:
        header = (2 << 16)
        return [header] + [w & MASK for w in block]   

MODE_ZERO_TAG, MODE_RLE_TAG, MODE_DELTA_TAG = 0, 1, 2

def decompress_zero(comp):
    header = comp[0] & MASK
    assert ((header >> 16) & 0x3) == MODE_ZERO_TAG, "header is not ZERO"
    bitmap = header & 0xFFFF
    block = [0] * N
    p = 1
    for i in range(N):
        if (bitmap >> i) & 1:
            block[i] = comp[p] & MASK
            p += 1
    return block

def decompress_rle(comp):
    header = comp[0] & MASK
    assert ((header >> 16) & 0x3) == MODE_RLE_TAG, "header is not RLE"
    num_runs = header & 0xFFFF
    block = []
    idx = 1
    for _ in range(num_runs):
        val = comp[idx] & MASK
        cnt = comp[idx + 1] & MASK
        idx += 2
        block += [val] * cnt
    assert len(block) == N, f"RLE decompressed to {len(block)} words (expected {N})"
    return block

def decompress_delta(comp):
    header = comp[0] & MASK
    assert ((header >> 16) & 0x3) == MODE_DELTA_TAG, "header is not DELTA"
    packed = (header >> 8) & 1
    if packed:
        base = comp[1] & MASK
        diffs = []
        for w in comp[2:6]:                    
            for b in range(4):
                diffs.append((w >> (8 * b)) & 0xFF)
        diffs = diffs[:N - 1]                      
        block = [base]
        for d in diffs:
            sd = d - 256 if d >= 128 else d        
            block.append((block[-1] + sd) & MASK)
        assert len(block) == N
        return block
    else:                                           
        return [w & MASK for w in comp[1:1 + N]]

def decompress(comp):
    tag = (comp[0] >> 16) & 0x3
    if tag == MODE_ZERO_TAG:
        return decompress_zero(comp)
    if tag == MODE_RLE_TAG:
        return decompress_rle(comp)
    if tag == MODE_DELTA_TAG:
        return decompress_delta(comp)
    raise ValueError(f"invalid header tag: {tag}")

MODE_ZERO, MODE_RLE, MODE_DELTA, MODE_RAW = 0, 1, 2, 3

def sbits(v):
    v &= MASK
    s = (v >> 31) & 1
    w = 1
    for i in range(31):
        if ((v >> i) & 1) != s:
            w = i + 2
    return w

def detect(block, tau1=None, tau2=None, wmax=None):

    zero_cnt = sum(1 for w in block if (w & MASK) == 0)
    run_cnt = sum(1 for i in range(1, N) if (block[i] & MASK) == (block[i - 1] & MASK))
    delta_w = 0
    for i in range(1, N):
        dw = sbits((block[i] - block[i - 1]) & MASK)
        if dw > delta_w:
            delta_w = dw
    lengths = [
        1 + (N - zero_cnt),
        1 + 2 * (N - run_cnt),
        6 if delta_w <= 8 else 17,
        N,
    ]
    mode = min(range(4), key=lambda m: lengths[m])
    return mode, zero_cnt, run_cnt, delta_w

def detect_word(block, tau1, tau2, wmax):
    mode, zc, rc, dw = detect(block, tau1, tau2, wmax)
    return ((dw & 0x3F) << 16) | ((rc & 0x3F) << 8) | ((zc & 0x3F) << 2) | (mode & 0x3)

TAU1, TAU2, WMAX = 8, 8, 8

def load_hex(path):
    words = []
    with open(path) as f:
        for line in f:
            for tok in line.split():
                words.append(int(tok, 16) & MASK)
    return words

def save_hex_1perline(words, path):
    with open(path, "w") as f:
        for w in words:
            f.write(f"{w & MASK:08X}\n")

def verify_roundtrip(src=None):
    if src is None:
        HERE = os.path.dirname(os.path.abspath(__file__))
        SRC = os.path.join(HERE, "tb_src_mixed.hex")
        if not os.path.exists(SRC):
            raise SystemExit(f"{SRC} not found -- generate the mixed source first.")
        src = load_hex(SRC)
    nblk = len(src) // N

    comp_fns = [("ZERO", comp_zero_hw, decompress_zero),
                ("RLE",  comp_rle_hw,  decompress_rle),
                ("DELTA", comp_delta_hw, decompress_delta)]

    print(f"== PHASE 4.2: Round-trip lossless ({nblk} blockss, N={N}) ==\n")
    print(f"  {'mode':<10}{'PASS':>8}{'FAIL':>8}{'result':>12}")
    print(f"  {'-'*38}")

    all_ok = True
    for name, cfn, dfn in comp_fns:
        npass = nfail = 0
        first_fail = None
        for b in range(nblk):
            block = [w & MASK for w in src[b * N:(b + 1) * N]]
            comp = cfn(block)
            rec = dfn(comp)
            if rec == block:
                npass += 1
            else:
                nfail += 1
                if first_fail is None:
                    first_fail = b
        ok = (nfail == 0)
        all_ok &= ok
        tag = "LOSSLESS" if ok else f"FAIL@blk{first_fail}"
        print(f"  {name:<10}{npass:>8}{nfail:>8}{tag:>12}")

    fns = {0: (comp_zero_hw, decompress_zero),
           1: (comp_rle_hw, decompress_rle),
           2: (comp_delta_hw, decompress_delta)}
    npass = nfail = 0
    first_fail = None
    for b in range(nblk):
        block = [w & MASK for w in src[b * N:(b + 1) * N]]
        m = detect(block, TAU1, TAU2, WMAX)[0]
        if m in fns:
            cfn, dfn = fns[m]
            rec = dfn(cfn(block))
        else:                                  
            rec = block
        if rec == block:
            npass += 1
        else:
            nfail += 1
            if first_fail is None:
                first_fail = b
    ok = (nfail == 0)
    all_ok &= ok
    tag = "LOSSLESS" if ok else f"FAIL@blk{first_fail}"
    print(f"  {'ADAPTIVE':<10}{npass:>8}{nfail:>8}{tag:>12}   <-- detector picks mode/block")

    print()
    if all_ok:
        print(f"  [PASS] Round-trip lossless 100%: decompress(compress(x)) == x "
              f"over all {nblk} blockss, all 3 modes + adaptive.")
    else:
        print("  [FAIL] Some block is not lossless -- see FAIL column above.")
    return all_ok

if __name__ == "__main__":
    import sys
    if "--roundtrip" in sys.argv:
        ok = verify_roundtrip()
        sys.exit(0 if ok else 1)

    HERE = os.path.dirname(os.path.abspath(__file__))
    SRC = os.path.join(HERE, "tb_src_mixed.hex")
    if not os.path.exists(SRC):
        raise SystemExit(f"{SRC} not found -- generate the mixed source first.")

    src = load_hex(SRC)
    nblk = len(src) // N
    print(f"Source: {len(src)} word, {nblk} blocks (N={N})\n")

    modes = [
        ("zero",  comp_zero_hw),
        ("rle",   comp_rle_hw),
        ("delta", comp_delta_hw),
    ]

    print(f"  {'mode':<8}{'EXP_LEN':>10}{'ratio':>10}")
    print(f"  {'-'*28}")
    for name, fn in modes:
        dest = []
        for b in range(nblk):
            dest += fn(src[b * N:(b + 1) * N])
        out_path = os.path.join(HERE, f"tb_expected_{name}_mixed.hex")
        save_hex_1perline(dest, out_path)
        ratio = (nblk * N) / len(dest) if dest else 0.0
        print(f"  {name:<8}{len(dest):>10}{ratio:>9.2f}x   -> {os.path.basename(out_path)}")

    print("\n  Copy the EXP_LEN values above into the matching testbench localparams.")

    print(f"\n== Phase 2: pattern_detect (tau1={TAU1}, tau2={TAU2}, wmax={WMAX}) ==")
    det_words = []
    dist = [0, 0, 0, 0]
    for b in range(nblk):
        block = src[b * N:(b + 1) * N]
        dw = detect_word(block, TAU1, TAU2, WMAX)
        det_words.append(dw)
        dist[dw & 0x3] += 1
    save_hex_1perline(det_words, os.path.join(HERE, "tb_expected_detect_mixed.hex"))
    names = ["ZERO", "RLE", "DELTA", "RAW"]
    print("  Mode distribution on mixed:",
          ", ".join(f"{names[m]}={dist[m]}" for m in range(4)))
    print(f"  tb_expected_detect_mixed.hex: {len(det_words)} block")

    print("\n== Adaptive (detect->compress) vs Fixed single-mode (compression ratio) ==")
    fns = {0: comp_zero_hw, 1: comp_rle_hw, 2: comp_delta_hw}

    def raw_len(block):
        return N

    def comp_len(block, m):
        return len(fns[m](block)) if m in fns else raw_len(block)

    orig = nblk * N

    for m, nm in [(0, "ZERO-only"), (1, "RLE-only"), (2, "DELTA-only")]:
        total = sum(comp_len(src[b * N:(b + 1) * N], m) for b in range(nblk))
        print(f"  {nm:<12} ratio={orig/total:.3f}x")
    total_ad = 0
    for b in range(nblk):
        block = src[b * N:(b + 1) * N]
        m = detect(block, TAU1, TAU2, WMAX)[0]
        total_ad += comp_len(block, m)
    print(f"  {'ADAPTIVE':<12} ratio={orig/total_ad:.3f}x   <-- detector picks mode/block")
