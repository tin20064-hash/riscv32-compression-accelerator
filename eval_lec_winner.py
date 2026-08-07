#!/usr/bin/env python3
import os, math
import golden_compress as gc

N = gc.N
DATASETS = [("temperature", "real_temp.hex"),
            ("light",       "real_light.hex"),
            ("voltage",     "real_volt.hex"),
            ("mixed",       "real_mixed.hex")]
HERE = os.path.dirname(os.path.abspath(__file__))
MODES = ["ZERO", "RLE", "DELTA", "LEC", "RAW"]


def lec_words(block):
    bits = 32
    prev = block[0]
    for w in block[1:]:
        d = w - prev
        n = abs(d).bit_length()
        plen = 2 if n == 0 else (3 if n <= 5 else n - 2)
        bits += plen + n
        prev = w
    return math.ceil(bits / 32)


def mode_lengths(block):
    return {
        "ZERO":  len(gc.comp_zero_hw(block)),
        "RLE":   len(gc.comp_rle_hw(block)),
        "DELTA": len(gc.comp_delta_hw(block)),
        "LEC":   lec_words(block),
        "RAW":   N,
    }


def pick(lengths, allowed):
    best = None
    for m in ["ZERO", "RLE", "DELTA", "LEC", "RAW"]:
        if m not in allowed:
            continue
        if best is None or lengths[m] < lengths[best]:
            best = m
    return best


def eval_file(path):
    words = gc.load_hex(path)
    nblk = len(words) // N
    tot_in = nblk * N
    out4 = out5 = outlec = 0
    win5 = {m: 0 for m in MODES}
    for b in range(nblk):
        blk = words[b * N:(b + 1) * N]
        L = mode_lengths(blk)
        m4 = pick(L, {"ZERO", "RLE", "DELTA", "RAW"})
        m5 = pick(L, {"ZERO", "RLE", "DELTA", "LEC", "RAW"})
        out4 += L[m4]
        out5 += L[m5]
        outlec += L["LEC"]
        win5[m5] += 1
    return nblk, tot_in, out4, out5, outlec, win5


def main():
    print("Winner distribution when LEC is added as a 5th candidate (word-based CR = 16/out_len)\n")
    hdr = "{:<12}{:>8}{:>8}{:>8}   {}".format(
        "dataset", "4-mode", "5-mode", "LECpure", "winner% [ZERO RLE DELTA LEC RAW]")
    print(hdr)
    print("-" * len(hdr))

    T_in = T4 = T5 = Tlec = 0
    Twin = {m: 0 for m in MODES}
    Tblk = 0
    for name, fn in DATASETS:
        path = os.path.join(HERE, fn)
        if not os.path.exists(path):
            print("  missing:", fn)
            continue
        nblk, tin, o4, o5, olec, win = eval_file(path)
        Tblk += nblk; T_in += tin; T4 += o4; T5 += o5; Tlec += olec
        for m in MODES:
            Twin[m] += win[m]
        wp = "  ".join("{:4.0f}".format(100.0 * win[m] / nblk) for m in MODES)
        print("{:<12}{:>8.2f}{:>8.2f}{:>8.2f}   {}".format(
            name, tin / o4, tin / o5, tin / olec, wp))

    print("-" * len(hdr))
    wp = "  ".join("{:4.0f}".format(100.0 * Twin[m] / Tblk) for m in MODES)
    print("{:<12}{:>8.2f}{:>8.2f}{:>8.2f}   {}".format(
        "OVERALL", T_in / T4, T_in / T5, T_in / Tlec, wp))

    print()
    print("Adaptation gain over just-use-LEC (5-mode / LEC-only): {:.3f}x".format(
        (T_in / T5) / (T_in / Tlec)))
    lec_share = 100.0 * Twin["LEC"] / Tblk
    print("LEC wins {:.1f}% of all blocks.".format(lec_share))
    if lec_share >= 90:
        print("=> LEC dominates: the 'adaptation among many engines' story weakens; "
              "reframe toward the never-inflate / composability guarantee.")
    else:
        print("=> Winner genuinely varies: the per-block adaptation story survives with LEC in the library.")


if __name__ == "__main__":
    main()
