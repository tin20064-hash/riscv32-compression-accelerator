# ModelSim unit test runner
# Usage: vsim -do run_modelsim_unit.do

if {![file exists work]} {
    vlib work
}
vmap work work

set SRC_DIR [file normalize [file dirname [info script]]]
cd $SRC_DIR

vlog -work work -sv +acc \
    if_stage.v id_stage.v ex_stage.v mem_stage.v \
    if_id_reg.v id_ex_reg.v pipeline_regs.v wb_hazard_fwd.v \
    tb_if_stage.v tb_id_stage.v tb_ex_stage.v tb_mem_stage.v

foreach tb {tb_if_stage tb_id_stage tb_ex_stage tb_mem_stage} {
    echo "===== Running $tb ====="
    vsim -c -voptargs=+acc work.$tb
    run -all
    quit -sim
}
