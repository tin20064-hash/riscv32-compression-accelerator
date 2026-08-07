# ===================================================================
# synth_paper.tcl -- DEDICATED PAPER BUILD (no demo/display logic mixed in)
# -------------------------------------------------------------------
# Top = cpu_top (pipeline + accelerator + detector + scratchpad),
# out-of-context: excludes the 1Hz clock divider, LEDs, 7-seg of the demo.
# This is the config used to extract NUMBERS for the paper; the board demo uses
# synth_phase5.tcl (fpga_top) rieng.
# Output: phase5_reports_paper/  (LOCKED numbers - not overwritten by demo builds)
# Run:  vivado -mode batch -source synth_paper.tcl
# ===================================================================
set PART xc7a100tcsg324-1
set OUTDIR [pwd]/phase5_reports_paper
file mkdir $OUTDIR

set RTL {
    cpu_top.v
    if_stage.v if_id_reg.v id_ex_reg.v pipeline_regs.v
    id_stage.v ex_stage.v mem_stage.v wb_hazard_fwd.v
    scratchpad.v
    Compress_accel.v comp_zero.v comp_rle.v comp_delta.v pattern_detect.v
}
foreach f $RTL { read_verilog $f }

# OOC: cap clock truc tiep len port clk (100 MHz target)
synth_design -top cpu_top -part $PART -mode out_of_context -flatten_hierarchy rebuilt
create_clock -name clk -period 10.000 [get_ports clk]

report_utilization -file $OUTDIR/01_synth_util.txt

opt_design
place_design
phys_opt_design
route_design

report_utilization               -file $OUTDIR/02_impl_util.txt
report_utilization -hierarchical -hierarchical_depth 4 -file $OUTDIR/03_util_hier.txt
report_timing_summary -delay_type max -max_paths 10 -file $OUTDIR/04_timing.txt
report_power                     -file $OUTDIR/05_power.txt

set TPERIOD 10.0
set wns [get_property SLACK [get_timing_paths -setup -max_paths 1 -nworst 1]]
if {$wns eq ""} { set wns 0 }
set fmax [expr {1000.0 / ($TPERIOD - $wns)}]

set sumf [open $OUTDIR/00_SUMMARY.txt w]
proc emit {ch s} { puts $ch $s; puts $s }
emit $sumf "==================================================================="
emit $sumf " PAPER BUILD -- cpu_top OOC (no demo display), $PART"
emit $sumf " Detector = EXACT-COST select (no threshold)"
emit $sumf "==================================================================="
emit $sumf [format " Target clock      : 100.00 MHz (period %.2f ns)" $TPERIOD]
emit $sumf [format " WNS (setup)       : %.3f ns" $wns]
emit $sumf [format " Fmax (achieved)   : %.2f MHz" $fmax]
close $sumf

puts "\n*** synth_paper.tcl HOAN TAT. So lieu bai bao o: $OUTDIR ***"
