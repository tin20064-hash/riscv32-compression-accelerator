#!/usr/bin/env python3
import os, sys, zlib, struct, math, csv

HERE = os.path.dirname(os.path.abspath(__file__))
N = 16
WORD_BYTES = 4
DATASETS = [("temperature", "real_temp.hex"),
            ("light",       "real_light.hex"),
            ("voltage",     "real_volt.hex"),
            ("mixed",       "real_mixed.hex")]

try:
    import lz4.block as _lz4
    HAVE_LZ4 = True
except ImportError:
    HAVE_LZ4 = False

try:
    import golden_compress as gc
    HAVE_GC = True
except Exception:
    HAVE_GC = False


def load_words(path):
    words = []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if line:
                words.append(int(line, 16) & 0xFFFFFFFF)
    return words


def blocks_to_bytes(words):
    return struct.pack("<%dI" % len(words), *words)


def raw_deflate(data, level):
    c = zlib.compressobj(level, zlib.DEFLATED, -15)
    return c.compress(data) + c.flush()


def lz4_block(data):
    return _lz4.compress(data, store_size=False)


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


def lec_bytes(words):
    return math.ceil(lec_bits(words) / 8)


def lzw_bytes(data):
    dict_size = 256
    table = {bytes([i]): i for i in range(dict_size)}
    MAXBITS = 12
    LIMIT = 1 << MAXBITS
    w = b""
    n_codes = 0
    for c in data:
        wc = w + bytes([c])
        if wc in table:
            w = wc
        else:
            n_codes += 1
            if dict_size < LIMIT:
                table[wc] = dict_size
                dict_size += 1
            w = bytes([c])
    if w:
        n_codes += 1
    return math.ceil(n_codes * MAXBITS / 8)


def pacomp_out_words(block):
    m = gc.detect(block)[0]
    if m == 0:
        return len(gc.comp_zero_hw(block))
    if m == 1:
        return len(gc.comp_rle_hw(block))
    if m == 2:
        return len(gc.comp_delta_hw(block))
    return N


def eval_dataset(words):
    nblk = len(words) // N
    in_bytes = nblk * N * WORD_BYTES
    res = {}

    pb = {"zlib-6": 0, "zlib-1": 0, "LEC": 0, "LZW": 0}
    if HAVE_LZ4:
        pb["LZ4"] = 0
    if HAVE_GC:
        pb["PA-COMP"] = 0

    for b in range(nblk):
        blk = words[b * N:(b + 1) * N]
        data = blocks_to_bytes(blk)
        pb["zlib-6"] += len(raw_deflate(data, 6))
        pb["zlib-1"] += len(raw_deflate(data, 1))
        pb["LEC"]    += lec_bytes(blk)
        pb["LZW"]    += lzw_bytes(data)
        if HAVE_LZ4:
            pb["LZ4"] += len(lz4_block(data))
        if HAVE_GC:
            pb["PA-COMP"] += pacomp_out_words(blk) * WORD_BYTES

    all_data = blocks_to_bytes(words)
    ws = {
        "zlib-6": len(raw_deflate(all_data, 6)),
        "zlib-1": len(raw_deflate(all_data, 1)),
        "LEC":    lec_bytes(words),
        "LZW":    lzw_bytes(all_data),
    }
    if HAVE_LZ4:
        ws["LZ4"] = len(lz4_block(all_data))

    res["in_bytes"] = in_bytes
    res["per_block"] = pb
    res["whole"] = ws
    return res


def cr(in_b, out_b):
    return in_b / out_b if out_b else float("inf")


def main():
    methods_pb = ["zlib-6", "zlib-1", "LEC", "LZW"]
    if HAVE_LZ4:
        methods_pb.append("LZ4")
    if HAVE_GC:
        methods_pb.append("PA-COMP")
    methods_ws = ["zlib-6", "zlib-1", "LEC", "LZW"] + (["LZ4"] if HAVE_LZ4 else [])

    totals_pb = {m: 0 for m in methods_pb}
    totals_ws = {m: 0 for m in methods_ws}
    total_in = 0
    rows = []

    print("Compression ratio (input_bytes / output_bytes), 64-byte blocks, N=16\n")
    if not HAVE_LZ4:
        print("[note] lz4 not installed -> LZ4 column skipped\n")
    if not HAVE_GC:
        print("[note] golden_compress import failed -> PA-COMP column skipped\n")

    print("== PER-BLOCK (matches PA-COMP deployment: each block compressed independently) ==")
    header = "{:<12}".format("dataset") + "".join("{:>10}".format(m) for m in methods_pb)
    print(header)
    print("-" * len(header))
    for name, fname in DATASETS:
        path = os.path.join(HERE, fname)
        if not os.path.exists(path):
            print("  missing:", fname)
            continue
        words = load_words(path)
        r = eval_dataset(words)
        total_in += r["in_bytes"]
        line = "{:<12}".format(name)
        row = {"dataset": name}
        for m in methods_pb:
            ratio = cr(r["in_bytes"], r["per_block"][m])
            totals_pb[m] += r["per_block"][m]
            line += "{:>10.2f}".format(ratio)
            row["pb_" + m] = round(ratio, 3)
        print(line)
        for m in methods_ws:
            totals_ws[m] += r["whole"][m]
            row["ws_" + m] = round(cr(r["in_bytes"], r["whole"][m]), 3)
        rows.append(row)

    line = "{:<12}".format("OVERALL")
    for m in methods_pb:
        line += "{:>10.2f}".format(cr(total_in, totals_pb[m]))
    print("-" * len(header))
    print(line)

    print("\n== WHOLE-STREAM (all blocks concatenated; generous to dictionary methods) ==")
    header2 = "{:<12}".format("dataset") + "".join("{:>10}".format(m) for m in methods_ws)
    print(header2)
    print("-" * len(header2))
    for row in rows:
        line = "{:<12}".format(row["dataset"])
        for m in methods_ws:
            line += "{:>10.2f}".format(row["ws_" + m])
        print(line)
    line = "{:<12}".format("OVERALL")
    for m in methods_ws:
        line += "{:>10.2f}".format(cr(total_in, totals_ws[m]))
    print("-" * len(header2))
    print(line)

    out_csv = os.path.join(HERE, "eval_baselines_results.csv")
    if rows:
        keys = ["dataset"] + ["pb_" + m for m in methods_pb] + ["ws_" + m for m in methods_ws]
        with open(out_csv, "w", newline="") as f:
            wtr = csv.DictWriter(f, fieldnames=keys)
            wtr.writeheader()
            for row in rows:
                wtr.writerow(row)
        print("\nWrote", os.path.basename(out_csv))


if __name__ == "__main__":
    main()
