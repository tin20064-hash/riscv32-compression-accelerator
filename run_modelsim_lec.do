# ModelSim runner for the LEC software-cost baseline (tb_lec_baseline.v)
# Self-contained: explicitly lists every module cpu_top depends on, so it
# does not rely on anything already sitting in a prior 'work' library.
#
# Usage:
#   1) In this folder, run: python asm_lec_baseline.py   (regenerates lec_baseline.hex)
#   2) In ModelSim:  do run_modelsim_lec.do
#      or from a shell: vsim -c -do run_modelsim_lec.do

if {![file exists work]} {
    vlib work
}
vmap work work

set SRC_DIR [file normalize [file dirname [info script]]]
cd $SRC_DIR

vlog -work work -sv +acc \
    if_stage.v \
    id_stage.v \
    ex_stage.v \
    mem_stage.v \
    if_id_reg.v \
    id_ex_reg.v \
    pipeline_regs.v \
    wb_hazard_fwd.v \
    scratchpad.v \
    comp_zero.v \
    comp_rle.v \
    comp_delta.v \
    pattern_detect.v \
    Compress_accel.v \
    cpu_top.v \
    tb_lec_baseline.v

vsim -voptargs=+acc work.tb_lec_baseline
run -all
