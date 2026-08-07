# ===================================================================
# synth_uart_demo.tcl -- Build the BITSTREAM for the UART demo (real hardware
# evidence: 14 real Intel Lab blocks, sending mode+out_len over UART).
# SEPARATE, does not use/overwrite synth_phase5.tcl (LED demo) or
# synth_paper.tcl (so lieu bai bao).
# Run:  vivado -mode batch -source synth_uart_demo.tcl
# ===================================================================
set PART xc7a100tcsg324-1
set OUTDIR [pwd]/phase5_reports_uart
file mkdir $OUTDIR

set RTL {
    uart_tx.v
    fpga_top_uart.v cpu_top.v
    if_stage.v if_id_reg.v id_ex_reg.v pipeline_regs.v
    id_stage.v ex_stage.v mem_stage.v wb_hazard_fwd.v
    scratchpad.v
    Compress_accel.v comp_zero.v comp_rle.v comp_delta.v pattern_detect.v
}
foreach f $RTL { read_verilog $f }
read_xdc nexys_a7_uart.xdc

synth_design -top fpga_top_uart -part $PART -flatten_hierarchy rebuilt
report_utilization -file $OUTDIR/01_synth_util.txt

opt_design
place_design
phys_opt_design
route_design

report_utilization              -file $OUTDIR/02_impl_util.txt
report_timing_summary -delay_type max -max_paths 10 -file $OUTDIR/03_timing.txt
report_power                    -file $OUTDIR/04_power.txt

write_bitstream -force $OUTDIR/fpga_top_uart.bit

puts "\n*** synth_uart_demo.tcl HOAN TAT. Bitstream + report o: $OUTDIR ***"
