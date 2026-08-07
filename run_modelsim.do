# ModelSim compile & run script for RISC-V CPU (IoT compression control core)
# Usage in ModelSim: do run_modelsim.do
# Or: vsim -do run_modelsim.do

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
    cpu_top.v \
    tb_cpu_top.v

vsim -voptargs=+acc work.tb_cpu_top
run -all
