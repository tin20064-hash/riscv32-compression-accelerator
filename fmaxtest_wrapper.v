`timescale 1ns/1ps
// ===================================================================
// fmaxtest_wrapper.v -- top THAT nap len board de do Fmax that
// -------------------------------------------------------------------
// CLK100MHZ vat ly (100MHz) -> MMCM (clk_wiz_fmax, IP Vivado) -> clk_test
// (custom frequency, set in synth_fmaxtest.tcl) -> fpga_top_fmaxtest
// (runs full-speed, clk_en=1 every cycle).
// If clk_test EXCEEDS the design's real Fmax, the final result (LED13=DELTA,
// 7-seg "2..17..06") will be WRONG or the circuit hangs -- that is the limit.
// ===================================================================
module fmaxtest_wrapper (
    input  wire        CLK100MHZ,
    input  wire        CPU_RESETN,
    output wire [15:0] LED,
    output wire [7:0]  AN,
    output wire [6:0]  SEG
);

    wire clk_test;
    wire mmcm_locked;

    // clk_wiz_fmax: Clocking Wizard IP, created by Tcl (create_ip ...)
    // CLK_IN1 = 100MHz that; CLK_OUT1 = clk_test (tan so test, xem .tcl)
    clk_wiz_fmax u_mmcm (
        .clk_in1  (CLK100MHZ),
        .reset    (~CPU_RESETN),
        .clk_out1 (clk_test),
        .locked   (mmcm_locked)
    );

    // hold the core in reset until the MMCM locks a stable clock
    wire rstn_sync = CPU_RESETN & mmcm_locked;

    fpga_top_fmaxtest u_core (
        .CLK100MHZ  (clk_test),
        .CPU_RESETN (rstn_sync),
        .LED        (LED),
        .AN         (AN),
        .SEG        (SEG)
    );

endmodule
