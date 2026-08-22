#!/usr/bin/env python3
# ===================================================================
# bin2hex.py -- Chuyen file .bin (objcopy -O binary) sang dinh dang
# Verilog hex (1 word 32-bit / dong, $readmemh nap duoc thang).
# -------------------------------------------------------------------
# Ly do co script nay thay vi dung thang "objcopy -O verilog": co
# --reverse-bytes cua objcopy KHONG dang tin cay giua cac phien ban
# binutils -- co ban binutils cu (2.35) can --reverse-bytes=4 moi ra
# dung thu tu byte, nhung ban moi (vd xPack rieng-none-elf-gcc, binutils
# 2.43+) lai bo qua co nay, khien file .hex sinh ra bi SAI thu tu byte
# (dao nguoc) ma khong bao loi gi ca -- chi phat hien duoc khi mo phong
# thay chuong trinh khong chay dung (roi phai doi chieu tay tung word).
#
# Script nay tu lam byte-swap bang Python (khong dua vao co cua
# objcopy nua) nen ra ket qua giong het nhau du dung binutils phien
# ban nao.
#
# Usage: python bin2hex.py <input.bin> <output.hex>
# ===================================================================
import struct
import sys


def main():
    if len(sys.argv) != 3:
        print("Usage: python bin2hex.py <input.bin> <output.hex>")
        sys.exit(1)
    inp, outp = sys.argv[1], sys.argv[2]

    with open(inp, "rb") as f:
        data = f.read()

    # dem du boi 0x00 cho tron 4 byte neu file .bin le byte (hiem khi xay ra)
    if len(data) % 4 != 0:
        data += b"\x00" * (4 - len(data) % 4)

    n_words = len(data) // 4
    words = struct.unpack("<{}I".format(n_words), data)  # little-endian -> word dung

    with open(outp, "w") as f:
        f.write("@00000000\n")
        for i in range(0, n_words, 4):
            chunk = words[i : i + 4]
            f.write(" ".join("%08X" % w for w in chunk) + "\n")

    print("-> {} ({} word, {} byte)".format(outp, n_words, len(data)))


if __name__ == "__main__":
    main()
