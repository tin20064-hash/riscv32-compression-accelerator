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

# Sao khong dung thang "objcopy -O verilog"? Da thu va bi loi: co
# --reverse-bytes cua objcopy KHONG dang tin cay giua cac phien ban
# binutils -- ban cu (binutils 2.35) can --reverse-bytes=4 moi dao dung
# thu tu byte, nhung ban moi (vd toolchain xPack rieng-none-elf-gcc,
# binutils 2.43+) lai IM LANG BO QUA co nay, khien file .hex bi SAI thu
# tu byte (dao nguoc moi word) MA KHONG BAO LOI GI CA -- chi phat hien
# duoc khi mo phong thay chuong trinh khong chay dung.
#
# De khong con phu thuoc vao hanh vi (khong on dinh) cua objcopy nua,
# xuat ra file .bin (dinh dang thuan byte, khong co khai niem "dao
# byte" nao ca) roi tu dao byte bang Python (bin2hex.py) -- cho ra
# cung 1 ket qua du dung binutils phien ban nao.
$(TARGET).hex: $(TARGET).elf bin2hex.py
	$(OBJCOPY) -O binary $< $(TARGET).bin
	python bin2hex.py $(TARGET).bin $@

# Xem thu chuong trinh da dich ra bao nhieu byte lenh (phai <= 1KB,
# xem link.ld / if_stage.v: mem[0:255]).
size: $(TARGET).elf
	$(SIZE) $(TARGET).elf

# Xem lenh may thuc te de doi chieu voi dieu ban da hoc ve R/I/S/B-type.
disasm: $(TARGET).elf
	$(OBJDUMP) -d $(TARGET).elf

clean:
	rm -f $(TARGET).elf $(TARGET).bin $(TARGET).hex
