#!/usr/bin/env python3
import os, re

OPC_CUSTOM0 = 0x0B

def reg(r):
    r = r.strip()
    assert r[0] == 'x', f"reg xau: {r}"
    n = int(r[1:]); assert 0 <= n < 32; return n

def imm(s):
    s = s.strip()
    return int(s, 0)

def u(val, bits):
    return val & ((1 << bits) - 1)

def R(funct7, rs2, rs1, funct3, rd, opc):
    return (u(funct7,7)<<25)|(u(rs2,5)<<20)|(u(rs1,5)<<15)|(u(funct3,3)<<12)|(u(rd,5)<<7)|u(opc,7)
def I(immv, rs1, funct3, rd, opc):
    return (u(immv,12)<<20)|(u(rs1,5)<<15)|(u(funct3,3)<<12)|(u(rd,5)<<7)|u(opc,7)
def S(immv, rs2, rs1, funct3, opc):
    i = u(immv,12)
    return (u(i>>5,7)<<25)|(u(rs2,5)<<20)|(u(rs1,5)<<15)|(u(funct3,3)<<12)|(u(i&0x1F,5)<<7)|u(opc,7)
def B(immv, rs2, rs1, funct3, opc):
    i = u(immv,13)
    b12=(i>>12)&1; b11=(i>>11)&1; b10_5=(i>>5)&0x3F; b4_1=(i>>1)&0xF
    return (b12<<31)|(b10_5<<25)|(u(rs2,5)<<20)|(u(rs1,5)<<15)|(u(funct3,3)<<12)|(b4_1<<8)|(b11<<7)|u(opc,7)
def Utype(immv, rd, opc):
    return (u(immv,20)<<12)|(u(rd,5)<<7)|u(opc,7)
def J(immv, rd, opc):
    i = u(immv,21)
    b20=(i>>20)&1; b10_1=(i>>1)&0x3FF; b11=(i>>11)&1; b19_12=(i>>12)&0xFF
    return (b20<<31)|(b10_1<<21)|(b11<<20)|(b19_12<<12)|(u(rd,5)<<7)|u(opc,7)

ALU_R  = {'add':(0,0),'sub':(0x20,0),'sll':(0,1),'slt':(0,2),'sltu':(0,3),
          'xor':(0,4),'srl':(0,5),'sra':(0x20,5),'or':(0,6),'and':(0,7)}
ALU_I  = {'addi':0,'slti':2,'sltiu':3,'xori':4,'ori':6,'andi':7}
SHIFTI = {'slli':(0,1),'srli':(0,5),'srai':(0x20,5)}
BR     = {'beq':0,'bne':1,'blt':4,'bge':5}

def assemble(lines):

    prog = []
    labels = {}
    addr = 0
    for raw in lines:
        line = raw.split('#')[0].strip()
        if not line: continue
        while ':' in line:
            lab, _, rest = line.partition(':')
            labels[lab.strip()] = addr
            line = rest.strip()
            if not line: break
        if not line: continue
        m = line.split(None, 1)
        mnem = m[0].lower()
        args = [a.strip() for a in m[1].split(',')] if len(m) > 1 else []
        prog.append((addr, mnem, args, raw))
        addr += 4

    words = []
    for (a, mnem, args, raw) in prog:
        try:
            w = enc(a, mnem, args, labels)
        except Exception as e:
            raise SystemExit(f"Loi dong: '{raw.strip()}' -> {e}")
        words.append(w & 0xFFFFFFFF)
    return words

def parse_mem(arg):

    mobj = re.match(r'(-?\w+)\(\s*(x\d+)\s*\)', arg)
    assert mobj, f"toan hang bo nho xau: {arg}"
    return imm(mobj.group(1)), reg(mobj.group(2))

def enc(a, mnem, args, labels):
    if mnem == 'nop':
        return I(0, 0, 0, 0, 0x13)
    if mnem in ALU_I:
        rd, rs1, im = reg(args[0]), reg(args[1]), imm(args[2])
        return I(im, rs1, ALU_I[mnem], rd, 0x13)
    if mnem in SHIFTI:
        f7, f3 = SHIFTI[mnem]; rd, rs1, sh = reg(args[0]), reg(args[1]), imm(args[2])
        return R(f7, sh, rs1, f3, rd, 0x13)
    if mnem in ALU_R:
        f7, f3 = ALU_R[mnem]; rd, rs1, rs2 = reg(args[0]), reg(args[1]), reg(args[2])
        return R(f7, rs2, rs1, f3, rd, 0x33)
    if mnem == 'lui':
        return Utype(imm(args[1]), reg(args[0]), 0x37)
    if mnem == 'auipc':
        return Utype(imm(args[1]), reg(args[0]), 0x17)
    if mnem == 'lw':
        off, rs1 = parse_mem(args[1]);  return I(off, rs1, 2, reg(args[0]), 0x03)
    if mnem == 'sw':
        off, rs1 = parse_mem(args[1]);  return S(off, reg(args[0]), rs1, 2, 0x23)
    if mnem in BR:
        rs1, rs2 = reg(args[0]), reg(args[1])
        off = labels[args[2]] - a
        return B(off, rs2, rs1, BR[mnem], 0x63)
    if mnem == 'jal':
        rd = reg(args[0]); off = labels[args[1]] - a
        return J(off, rd, 0x6F)
    if mnem == 'jalr':
        off, rs1 = parse_mem(args[1]);  return I(off, rs1, 0, reg(args[0]), 0x67)

    if mnem == 'pdetect':
        return R(0, reg(args[2]), reg(args[1]), 0, reg(args[0]), OPC_CUSTOM0)
    if mnem == 'ccompr':
        return R(0, reg(args[1]), reg(args[0]), 1, 0, OPC_CUSTOM0)
    if mnem == 'cstat':
        return R(0, 0, 0, 2, reg(args[0]), OPC_CUSTOM0)
    raise SystemExit(f"unsupported instruction: {mnem}")

PROGRAM = r"""
    # ---- init ----
    lui   x5, 0x1            # x5 = 0x1000
    addi  x5, x5, 0xC0       # dst byte = 0x10C0 (word 48)
    addi  x6, x0, 0          # i = 0
    addi  x7, x0, 3          # NUM_BLK = 3
loop:
    slli  x8, x6, 6          # i*64
    lui   x9, 0x1            # 0x1000
    add   x10, x9, x8        # src byte = 0x1000 + i*64
    # ---- detect ----
    pdetect x11, x10, x0     # thr = x0 = 0 -> default
wait1:
    cstat x12
    srli  x13, x12, 30       # done bit = status[30]
    andi  x13, x13, 1
    beq   x13, x0, wait1
    andi  x14, x12, 3        # mode = det_word[1:0]
    or    x15, x5, x14       # op_b = dst | mode
    # ---- compress ----
    ccompr x10, x15
wait2:
    cstat x16
    srli  x17, x16, 30
    andi  x17, x17, 1
    beq   x17, x0, wait2
    andi  x18, x16, 0x7FF    # out_len
    # ---- store results for the testbench to check ----
    slli  x20, x6, 2         # i*4 -> data_mem[i]
    sw    x14, 0(x20)        # data_mem[i] = mode
    addi  x21, x20, 64       # (i+16)*4 -> data_mem[16+i]
    sw    x18, 0(x21)        # data_mem[16+i] = out_len
    # ---- advance dest pointer ----
    slli  x19, x18, 2
    add   x5, x5, x19        # dst += out_len*4
    addi  x6, x6, 1
    bne   x6, x7, loop
halt:
    jal   x0, halt
"""

if __name__ == "__main__":
    HERE = os.path.dirname(os.path.abspath(__file__))
    words = assemble(PROGRAM.splitlines())

    while len(words) < 256:
        words.append(0)
    out = os.path.join(HERE, "demo_pipeline.hex")
    with open(out, "w") as f:
        for w in words:
            f.write(f"{w:08X}\n")
    nins = sum(1 for l in PROGRAM.splitlines()
               if l.split('#')[0].strip() and not l.split('#')[0].strip().endswith(':')
               and ':' not in l.split('#')[0] or
               (l.split('#')[0].strip() and ':' in l.split('#')[0] and l.split('#')[0].split(':',1)[1].strip()))
    print(f"  demo_pipeline.hex: {out}")
    print(f"  program word count (leading non-zero): see hex; total 256 words (padded).")
