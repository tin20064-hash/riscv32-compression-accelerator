`timescale 1ns/1ps
// ===================================================================
// tb_sw_baseline.v -- MEASURE PURE-SOFTWARE compress CYCLES on cpu_top
// -------------------------------------------------------------------
// Nap sw_baseline.hex (3 routine RV32I: ZERO/RLE/DELTA) + 3 block demo
// (demo_src.hex, SAME blocks the hardware measured at 17/37/23 busy cycles).
// Capture a timestamp each time the SW program writes the marker address (word 253):
//   marker 1-2 = ZERO, 3-4 = RLE, 5-6 = DELTA.
// Check compressed output == demo_expected_dest.hex (same HW format) and
// out_len == [5,5,6] -> prove SW does the RIGHT work before trusting cycles.
// ===================================================================
module tb_sw_baseline;
    reg clk = 0, rst_n = 0, clk_en = 1;
    wire [31:0] debug_data, accel_dbg;
    always #5 clk = ~clk;

    cpu_top dut (.clk(clk), .rst_n(rst_n), .clk_en(clk_en),
                 .debug_data(debug_data), .accel_dbg(accel_dbg));

    // cycle counter
    integer cyc = 0;
    always @(posedge clk) if (rst_n) cyc = cyc + 1;

    // catch marker: sw to word 253 (byte 1012) in data_mem
    integer tstamp [1:6];
    integer nmark = 0;
    always @(posedge clk) begin
        if (rst_n && dut.u_mem_stage.mem_write && !dut.u_mem_stage.spad_sel
            && dut.u_mem_stage.word_addr == 8'd253) begin
            nmark = nmark + 1;
            if (nmark <= 6) tstamp[nmark] = cyc;
        end
    end

    reg [31:0] exp_dest [0:15];
    reg [31:0] src_tmp  [0:47];
    integer i, errors;

    initial begin
        $readmemh("demo_expected_dest.hex", exp_dest);
        #1;
        $readmemh("sw_baseline.hex", dut.u_if_stage.u_imem.mem);
        $readmemh("demo_src.hex", src_tmp);
        for (i = 0; i < 48; i = i + 1)
            dut.u_mem_stage.data_mem[i] = src_tmp[i];

        repeat (4) @(posedge clk);
        rst_n = 1;

        wait (nmark >= 6);
        repeat (10) @(posedge clk);

        errors = 0;
        $display("\n  == SOFTWARE BASELINE (pure RV32I, no accelerator) ==");
        $display("  ZERO  sw: %0d cycle   (HW busy: 17)", tstamp[2]-tstamp[1]);
        $display("  RLE   sw: %0d cycle   (HW busy: 37)", tstamp[4]-tstamp[3]);
        $display("  DELTA sw: %0d cycle   (HW busy: 23)", tstamp[6]-tstamp[5]);

        // check correctness: out_len
        if (dut.u_mem_stage.data_mem[250] !== 32'd5) begin
            errors = errors + 1;
            $display("  [LEN FAIL] ZERO len=%0d exp=5", dut.u_mem_stage.data_mem[250]);
        end
        if (dut.u_mem_stage.data_mem[251] !== 32'd5) begin
            errors = errors + 1;
            $display("  [LEN FAIL] RLE len=%0d exp=5", dut.u_mem_stage.data_mem[251]);
        end
        if (dut.u_mem_stage.data_mem[252] !== 32'd6) begin
            errors = errors + 1;
            $display("  [LEN FAIL] DELTA len=%0d exp=6", dut.u_mem_stage.data_mem[252]);
        end
        // check output == golden (ZERO @64, RLE @96, DELTA @128)
        for (i = 0; i < 5; i = i + 1)
            if (dut.u_mem_stage.data_mem[64+i] !== exp_dest[i]) begin
                errors = errors + 1;
                $display("  [ZERO FAIL] [%0d] got=%08h exp=%08h", i,
                         dut.u_mem_stage.data_mem[64+i], exp_dest[i]);
            end
        for (i = 0; i < 5; i = i + 1)
            if (dut.u_mem_stage.data_mem[96+i] !== exp_dest[5+i]) begin
                errors = errors + 1;
                $display("  [RLE FAIL] [%0d] got=%08h exp=%08h", i,
                         dut.u_mem_stage.data_mem[96+i], exp_dest[5+i]);
            end
        for (i = 0; i < 6; i = i + 1)
            if (dut.u_mem_stage.data_mem[128+i] !== exp_dest[10+i]) begin
                errors = errors + 1;
                $display("  [DELTA FAIL] [%0d] got=%08h exp=%08h", i,
                         dut.u_mem_stage.data_mem[128+i], exp_dest[10+i]);
            end

        if (errors == 0)
            $display("  [PASS] SW output MATCHES golden (same format as HW) -> cycle counts are valid.");
        else
            $display("  [FAIL] %0d loi -> so cycle CHUA dang tin.", errors);
        $finish;
    end

    initial begin #500000; $display("  [TIMEOUT] nmark=%0d", nmark); $finish; end
endmodule
