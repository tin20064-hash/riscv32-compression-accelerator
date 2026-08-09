# ===================================================================
# crt0.S -- Doan khoi dong toi thieu cho RV32I 5-stage core (custom-0)
# -------------------------------------------------------------------
# Day la lenh DAU TIEN CPU chay sau reset (dat tai dia chi 0x0, xem
# link.ld va if_stage.v: "if (!rst_n) pc_out <= 32'h0000_0000;").
# Khong the viet doan nay bang C: code C do GCC dich ra gan nhu luon
# gia dinh san sp (x2) da hop le truoc do -- neu tu C thi roi vao
# vong luan quan "can sp hop le de chay code thiet lap sp".
#
# Lam dung 2 viec, theo dung thu tu:
#   1) Gan sp  = _stack_top (dinh vung DATA, xem link.ld)
#   2) Xoa trang vung .bss ve 0 -- BAT BUOC, vi demo_pipeline.c co
#      2 bien toan cuc khong khoi tao (mode_log[], len_log[]), theo
#      chuan C phai bang 0 luc chuong trinh vua chay. mem_stage.v co
#      1 vong lap xoa data_mem ve 0 nhung CHI CHAY 1 LAN LUC BITSTREAM
#      MOI NAP (khoi dong mo phong / lan config FPGA dau tien) --
#      KHONG chay lai khi bam nut reset vat ly sau do, nen khong the
#      trong cay vao no.
#
# Ve thanh ghi gp (x3, "global pointer"): KHONG gan o day. Bo qua co
# tinh vi doan nay chi dung khi build voi -mno-relax (xem Makefile) --
# tat toi uu "linker relaxation" cua GNU ld thi code khong con phat
# sinh lenh truy cap kieu %gp_rel nua, nen gp khong con can thiet.
# Neu sau nay BAT lai relaxation, phai quay lai bo sung doan gan gp
# o day truoc khi goi vao C.
# ===================================================================

    .section .text.start, "ax"
    .globl  _start
    .type   _start, @function

_start:
    # ---- 1) thiet lap con tro ngan xep ----
    lui   sp, %hi(_stack_top)
    addi  sp, sp, %lo(_stack_top)

    # ---- 2) xoa vung .bss ve 0 (vong lap word-by-word) ----
    lui   t0, %hi(_bss_start)
    addi  t0, t0, %lo(_bss_start)      # t0 = con tro dang xoa
    lui   t1, %hi(_bss_end)
    addi  t1, t1, %lo(_bss_end)        # t1 = dia chi ket thuc .bss
bss_clear_loop:
    bge   t0, t1, bss_clear_done       # da xoa het -> thoat vong lap
    sw    zero, 0(t0)
    addi  t0, t0, 4
    jal   x0, bss_clear_loop
bss_clear_done:

    # ---- 3) nhay vao code C (ham c_entry trong demo_pipeline.c) ----
    jal   ra, c_entry

    # c_entry khong bao gio return (ban than no da la vong lap vo han),
    # nhung de an toan neu lo return thi dung yen tai day, khong chay
    # lung tung sang vung nho trong/rac.
halt:
    jal   x0, halt

    .size _start, . - _start
