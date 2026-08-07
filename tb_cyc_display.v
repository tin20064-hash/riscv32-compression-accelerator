`timescale 1ns/1ps
// ===================================================================
// tb_cyc_display.v -- VERIFY the display cycle-counter logic (fpga_top)
// -------------------------------------------------------------------
// Run the real demo on cpu_top, applying the EXACT count+latch cyc_lat logic
// as in fpga_top.v, printing cyc_lat after each block to cross-check with
// the figures measured by tb_stage_count.v (expected 17 / 37 / 23).
// ===================================================================
module tb_cyc_display;
    reg clk = 0, rst_n = 0, clk_en = 1;
    wire [31:0] debug_data;
    wire [31:0] accel_dbg;
    always #5 clk = ~clk;

    cpu_top dut (.clk(clk), .rst_n(rst_n), .clk_en(clk_en), .debug_data(debug_data), .accel_dbg(accel_dbg));

    wire       a_done   = accel_dbg[31];
    wire       a_lastop = accel_dbg[30];
    wire       a_busy   = accel_dbg[29];

    reg        a_busy_d;
    reg [7:0]  cyc_cnt;
    reg [7:0]  cyc_lat;
    integer    block_idx = 0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_busy_d <= 1'b0;
            cyc_cnt  <= 8'd0;
            cyc_lat  <= 8'd0;
        end else begin
            a_busy_d <= a_busy;
            if (a_busy & ~a_busy_d) begin
                cyc_cnt <= 8'd0;
            end else if (a_busy & clk_en) begin
                cyc_cnt <= cyc_cnt + 8'd1;
            end
            if (~a_busy & a_busy_d & ~a_lastop) begin
                cyc_lat <= cyc_cnt;
                $display("  Block %0d: cyc_lat (7-seg display) = %0d", block_idx, cyc_cnt);
                block_idx = block_idx + 1;
            end
        end
    end

    initial begin
        #1;
        $readmemh("demo_pipeline.hex", dut.u_if_stage.u_imem.mem);
        $readmemh("demo_src.hex",      dut.u_scratchpad.mem);
        repeat (4) @(posedge clk);
        rst_n = 1;
        #6000;
        $display("  [DONE] expected: 17 (ZERO), 37 (RLE), 23 (DELTA)");
        $finish;
    end
endmodule
