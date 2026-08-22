# ===================================================================
# run_modelsim_all.do -- Chay TOAN BO 18 testbench trong repo, 1 lenh duy nhat.
# -------------------------------------------------------------------
# Usage:
#   vsim -c -do run_modelsim_all.do          (tu shell / Git Bash)
#   do run_modelsim_all.do                    (trong ModelSim GUI)
#
# Truoc khi chay, dam bao cac file .hex sau da co san trong thu muc
# (da co san trong repo; chi can sinh lai neu ban vua sua code nguon):
#   python asm_riscv.py            -> demo_pipeline.hex   (hoac dung GCC,
#                                       xem Makefile / README muc 12)
#   python asm_sw_baseline.py      -> sw_baseline.hex
#   python asm_lec_baseline.py     -> lec_baseline.hex
#   python asm_uart_demo.py        -> uart_demo.hex
#   python gen_demo.py             -> demo_src.hex, demo_expected_dest.hex
#   python golden_compress.py      -> tb_expected_*_mixed.hex
#
# Ket qua: doc trong Transcript, tim dong "===== <ten tb> =====" de biet
# dang o testbench nao, roi tim dong PASS/FAIL/TIMEOUT ngay phia tren
# dong "----- HET <ten tb> -----" ke tiep. Xem README muc 12 de biet
# dung tim chu gi (PASS/FAIL) cho tung testbench.
# ===================================================================

if {![file exists work]} {
    vlib work
}
vmap work work

set SRC_DIR [file normalize [file dirname [info script]]]
cd $SRC_DIR

# ---- bien dich toan bo RTL + toan bo testbench 1 lan ----
vlog -work work -sv +acc \
    if_stage.v id_stage.v ex_stage.v mem_stage.v \
    if_id_reg.v id_ex_reg.v pipeline_regs.v wb_hazard_fwd.v \
    scratchpad.v comp_zero.v comp_rle.v comp_delta.v pattern_detect.v Compress_accel.v \
    cpu_top.v uart_tx.v fpga_top_uart_fastsim.v \
    tb_if_stage.v tb_id_stage.v tb_ex_stage.v tb_mem_stage.v \
    tb_cpu_top.v \
    tb_comp_zero.v tb_comp_rle.v tb_comp_delta.v tb_pattern_detect.v tb_compress_top.v \
    tb_demo_pipeline.v tb_demo_sparse.v tb_cyc_display.v \
    tb_sw_baseline.v tb_lec_baseline.v \
    tb_uart_tx.v tb_fpga_top_uart.v \
    tb_throughput.v

# ---- chay lan luot tung testbench, moi cai la 1 vsim rieng ----
foreach tb {
    tb_if_stage tb_id_stage tb_ex_stage tb_mem_stage
    tb_cpu_top
    tb_comp_zero tb_comp_rle tb_comp_delta tb_pattern_detect tb_compress_top
    tb_demo_pipeline tb_demo_sparse tb_cyc_display
    tb_sw_baseline tb_lec_baseline
    tb_uart_tx tb_fpga_top_uart
    tb_throughput
} {
    echo "===== $tb ====="
    vsim -c -voptargs=+acc work.$tb
    run -all
    quit -sim
    echo "----- HET $tb -----"
}

echo "===== DA CHAY XONG CA 18 TESTBENCH -- keo len xem tung khoi de doi chieu PASS/FAIL ====="
