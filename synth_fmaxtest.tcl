# ===================================================================
# synth_fmaxtest.tcl -- build a bitstream to MEASURE REAL FMAX on silicon
# -------------------------------------------------------------------
# Uses PROJECT MODE (unlike synth_paper.tcl/synth_phase5.tcl which are non-project)
# vi can tich hop IP Clocking Wizard (MMCM) -- project mode on dinh hon
# for an IP-based flow via Tcl.
#
# CHANGE TEST FREQUENCY: edit the TEST_FREQ_MHZ line below and rerun. Each run
# OVERWRITES the old bitstream -- rename fpga_top.bit (e.g. copy to
# fmaxtest_80mhz.bit) before changing frequency if you want to keep several.
#
# Run:  vivado -mode batch -source synth_fmaxtest.tcl
# Output: fmaxtest_proj/fmaxtest_proj.runs/impl_1/fmaxtest_wrapper.bit
# ===================================================================
set TEST_FREQ_MHZ 200.000
;# <<< EDIT THIS TO CHANGE TEST FREQUENCY (e.g. 80.000 / 100.000 / 120.000) >>>

set PART       xc7a100tcsg324-1
set PROJ_NAME  fmaxtest_proj
set PROJ_DIR   [pwd]/fmaxtest_proj

file delete -force $PROJ_DIR
create_project $PROJ_NAME $PROJ_DIR -part $PART -force

set RTL {
    fmaxtest_wrapper.v fpga_top_fmaxtest.v
    cpu_top.v if_stage.v if_id_reg.v id_ex_reg.v pipeline_regs.v
    id_stage.v ex_stage.v mem_stage.v wb_hazard_fwd.v
    scratchpad.v Compress_accel.v comp_zero.v comp_rle.v comp_delta.v
    pattern_detect.v
}
add_files -norecurse $RTL
add_files -fileset constrs_1 -norecurse [pwd]/nexys_a7.xdc
set_property top fmaxtest_wrapper [current_fileset]

# --- create the Clocking Wizard IP (MMCM) at the test frequency ---
create_ip -name clk_wiz -vendor xilinx.com -library ip -module_name clk_wiz_fmax
set_property -dict [list \
    CONFIG.PRIM_IN_FREQ {100.000} \
    CONFIG.CLKOUT1_REQUESTED_OUT_FREQ $TEST_FREQ_MHZ \
    CONFIG.USE_LOCKED {true} \
    CONFIG.USE_RESET {true} \
    CONFIG.RESET_TYPE {ACTIVE_HIGH} \
    CONFIG.CLKIN1_JITTER_PS {100.0} \
] [get_ips clk_wiz_fmax]
generate_target all [get_files $PROJ_DIR/$PROJ_NAME.srcs/sources_1/ip/clk_wiz_fmax/clk_wiz_fmax.xci]

update_compile_order -fileset sources_1

puts "\n*** DANG SYNTH+IMPL o tan so test: ${TEST_FREQ_MHZ} MHz ***\n"

launch_runs synth_1 -jobs 4
wait_on_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

set BIT_SRC  $PROJ_DIR/$PROJ_NAME.runs/impl_1/fmaxtest_wrapper.bit
set BIT_DST  [pwd]/fmaxtest_${TEST_FREQ_MHZ}MHz.bit
file copy -force $BIT_SRC $BIT_DST

puts "\n*** DONE. Test frequency: ${TEST_FREQ_MHZ} MHz ***"
puts "*** Bitstream: $BIT_DST ***"
puts "*** Load this file onto the board, press CPU_RESET, read LED13+7-seg. ***"
puts "*** Correct: LED13 on, 7-seg shows '2..17..06' -> PASSES at this frequency ***"
