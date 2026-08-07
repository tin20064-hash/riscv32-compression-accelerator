# ===================================================================
# synth_phase5.tcl -- Phase 5: Synthesis + Implementation (Vivado)
# -------------------------------------------------------------------
# Non-project flow (in-memory) for Nexys A7-100T (xc7a100tcsg324-1).
# Synth + place + route ca thiet ke (fpga_top = cpu_top + accel + detector),
# then export: utilization, timing (-> Fmax), power, and hierarchical util
# (to isolate pattern_detect cost = detection overhead for Phase 5.2).
#
# Run:
#   vivado -mode batch -source synth_phase5.tcl
# ===================================================================
set PART xc7a100tcsg324-1
set OUTDIR [pwd]/phase5_reports
file mkdir $OUTDIR

# --- RTL list (EXCLUDING tb_*.v) ---
set RTL {
    fpga_top.v cpu_top.v
    if_stage.v if_id_reg.v id_ex_reg.v pipeline_regs.v
    id_stage.v ex_stage.v mem_stage.v wb_hazard_fwd.v
    scratchpad.v
    Compress_accel.v comp_zero.v comp_rle.v comp_delta.v pattern_detect.v
}
foreach f $RTL { read_verilog $f }
read_xdc nexys_a7.xdc

# --- SYNTHESIS ---
synth_design -top fpga_top -part $PART -flatten_hierarchy rebuilt
report_utilization -file $OUTDIR/01_synth_util.txt

# --- IMPLEMENTATION ---
opt_design
place_design
phys_opt_design
route_design

# --- REPORTS ---
report_utilization              -file $OUTDIR/02_impl_util.txt
report_utilization -hierarchical -hierarchical_depth 4 -file $OUTDIR/03_util_hier.txt
report_timing_summary -delay_type max -max_paths 10 -file $OUTDIR/04_timing.txt
report_power                    -file $OUTDIR/05_power.txt

# --- MAIN NUMBER SUMMARY (print + write file) ---
set TPERIOD 10.0   ;# 100 MHz -> 10 ns period
set wns [get_property SLACK [get_timing_paths -setup -max_paths 1 -nworst 1]]
if {$wns eq ""} { set wns 0 }
set fmax [expr {1000.0 / ($TPERIOD - $wns)}]

# helper to count used resources
proc used {stat} { return [get_property $stat [report_utilization -return_string]] }

set sumf [open $OUTDIR/00_SUMMARY.txt w]
proc emit {ch s} { puts $ch $s; puts $s }
emit $sumf "==================================================================="
emit $sumf " PHASE 5 -- SYNTH + IMPL RESULTS (Nexys A7-100T, $PART)"
emit $sumf "==================================================================="
emit $sumf [format " Target clock      : 100.00 MHz (period %.2f ns)" $TPERIOD]
emit $sumf [format " WNS (setup)       : %.3f ns" $wns]
emit $sumf [format " Fmax (achieved)   : %.2f MHz" $fmax]
emit $sumf ""

# Re-read the utilization numbers from the report (simple grep)
emit $sumf " --- Utilization (xem 02_impl_util.txt) ---"
emit $sumf " --- Hierarchical detector (xem 03_util_hier.txt: instance u_detect) ---"
emit $sumf " --- Power (xem 05_power.txt: Total On-Chip Power) ---"
close $sumf

# --- BITSTREAM (file .bit de nap len Nexys A7) ---
# If timing is not met (negative WNS @100MHz) the bitstream is STILL created, just
# a warning; the design runs fine at a lower speed. write_bitstream runs its own
# DRC; -force overwrites the old file.
write_bitstream -force $OUTDIR/fpga_top.bit
puts "*** BITSTREAM: $OUTDIR/fpga_top.bit ***"

puts "\n*** synth_phase5.tcl HOAN TAT. Bao cao + bitstream o: $OUTDIR ***"
