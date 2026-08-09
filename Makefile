# ===================================================================
# Makefile -- build demo_pipeline.hex bang RISC-V GCC that (thay vi
#             asm_riscv.py) cho RV32I 5-stage core + custom-0 PA-COMP.
# -------------------------------------------------------------------
# Dung:
#   make                  # build demo_pipeline.hex (mac dinh)
#   make demo_pipeline.hex
#   make clean
#   make CROSS=riscv64-unknown-elf-   # doi ten prefix toolchain neu khac
# ===================================================================

CROSS   ?= riscv32-unknown-elf-
CC       = $(CROSS)gcc
OBJCOPY  = $(CROSS)objcopy
OBJDUMP  = $(CROSS)objdump
SIZE     = $(CROSS)size

# -march=rv32i -mabi=ilp32 : CPU chi cai RV32I thuan, khong duoc de GCC
#   phat sinh nhan/chia/dau phay dong.
# -nostdlib -ffreestanding  : khong OS, khong thu vien C chuan.
# -mno-relax                : tat "linker relaxation" dua vao thanh ghi
#   gp (x3) -- crt0.S khong gan gp, xem chu thich trong crt0.S.
CFLAGS   = -march=rv32i -mabi=ilp32 -nostdlib -ffreestanding -Os \
           -mno-relax -Wall -Wextra -ffunction-sections -fdata-sections
LDFLAGS  = -T link.ld -nostdlib -Wl,--no-relax -Wl,--gc-sections

SRCS     = crt0.S demo_pipeline.c
TARGET   = demo_pipeline

.PHONY: all clean size disasm

all: $(TARGET).hex

$(TARGET).elf: $(SRCS) link.ld
	$(CC) $(CFLAGS) $(LDFLAGS) $(SRCS) -o $@

# --verilog-data-width=4 : gom 4 byte / dong (khop voi "reg [31:0] mem[0:255]"
#   trong if_stage.v -- neu de mac dinh, objcopy xuat 1 BYTE/dong, $readmemh
#   se nap sai hoan toan (moi word 32-bit chi con 8 bit thap co nghia).
# --reverse-bytes=4      : ELF luu lenh theo little-endian (byte thap truoc),
#   objcopy noi thang 4 byte file lien tiep thanh 1 token khong doi thu tu
#   -> phai dao nguoc 4 byte/nhom de ra dung gia tri word (vd byte file
#   "37 01 00 00" phai thanh "00000137", khong phai "37010000").
$(TARGET).hex: $(TARGET).elf
	$(OBJCOPY) -O verilog --verilog-data-width=4 --reverse-bytes=4 $< $@
	@echo "-> $@ ($$(wc -l < $@) dong, nap duoc thang bang \$$readmemh)"

# Xem thu chuong trinh da dich ra bao nhieu byte lenh (phai <= 1KB,
# xem link.ld / if_stage.v: mem[0:255]).
size: $(TARGET).elf
	$(SIZE) $(TARGET).elf

# Xem lenh may thuc te de doi chieu voi dieu ban da hoc ve R/I/S/B-type.
disasm: $(TARGET).elf
	$(OBJDUMP) -d $(TARGET).elf

clean:
	rm -f $(TARGET).elf $(TARGET).hex
