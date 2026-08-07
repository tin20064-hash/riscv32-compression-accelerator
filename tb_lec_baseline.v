`timescale 1ns/1ps
// ===================================================================
// tb_lec_baseline.v -- measure PURE-SOFTWARE LEC length-computation
// cycles on cpu_top, same technique and same block as tb_sw_baseline.v.
// -------------------------------------------------------------------
// Loads lec_baseline.hex (RV32I program, see asm_lec_baseline.py) and
// demo_src.hex (same file tb_sw_baseline.v uses; word 32..47 is the
// "block_delta" block DELTA's own SW baseline already measures at 548
// cycles). Captures a timestamp each time the program writes the
// marker address (word 253): marker 1 = begin, marker 2 = done.
// Checks word 250 == 4 (out_len_words) and word 251 == 102 (total
// bits) against the golden LEC bit-cost model BEFORE trusting the
// cycle count -- same discipline as tb_sw_baseline.v.
//
// IMPORTANT (read before citing the number this prints): this program
// measures LEC's classification pass only (diff -> abs -> bit-length
// -> prefix-code length -> running total), not the bit-packing pass a
// real encoder also needs. The cycle count is therefore a LOWER BOUND
// on LEC's true software cost -- report it as "at least N cycles."
// ===================================================================
module tb_lec_baseline;
    reg clk = 0, rst_n = 0, clk_en = 1;
    wire [31:0] debug_data, accel_dbg;
    always #5 clk = ~clk;

    cpu_top dut (.clk(clk), .rst_n(rst_n), .clk_en(clk_en),
                 .debug_data(debug_data), .accel_dbg(accel_dbg));

    integer cyc = 0;
    always @(posedge clk) if (rst_n) cyc = cyc + 1;

    // catch marker: sw to word 253 (byte 1012) in data_mem
    integer tstamp [1:2];
    integer nmark = 0;
    always @(posedge clk) begin
        if (rst_n && dut.u_mem_stage.mem_write && !dut.u_mem_stage.spad_sel
            && dut.u_mem_stage.word_addr == 8'd253) begin
            nmark = nmark + 1;
            if (nmark <= 2) tstamp[nmark] = cyc;
        end
    end

    reg [31:0] src_tmp [0:47];
    integer i, errors;

    initial begin
        $readmemh("demo_src.hex", src_tmp);
        #1;
        $readmemh("lec_baseline.hex", dut.u_if_stage.u_imem.mem);
        for (i = 0; i < 48; i = i + 1)
            dut.u_mem_stage.data_mem[i] = src_tmp[i];

        repeat (4) @(posedge clk);
        rst_n = 1;

        wait (nmark >= 2);
        repeat (10) @(posedge clk);

        errors = 0;
        $display("\n  == SOFTWARE LEC LENGTH COMPUTATION (pure RV32I, no accelerator) ==");
        $display("  LEC length-only sw: %0d cycle   (DELTA sw on the SAME block: 548 cycle, HW: 23 cycle)",
                  tstamp[2]-tstamp[1]);
        $display("  NOTE: this is the classification pass only (no bitstream packing).");
        $display("        Treat the printed number as a LOWER BOUND on LEC's true SW cost.");

        if (dut.u_mem_stage.data_mem[250] !== 32'd4) begin
            errors = errors + 1;
            $display("  [LEN FAIL] out_len_words=%0d exp=4", dut.u_mem_stage.data_mem[250]);
        end
        if (dut.u_mem_stage.data_mem[251] !== 32'd102) begin
            errors = errors + 1;
            $display("  [BITS FAIL] total_bits=%0d exp=102", dut.u_mem_stage.data_mem[251]);
        end

        if (errors == 0)
            $display("  [PASS] SW output MATCHES the golden LEC bit-cost model -> cycle count is valid.");
        else
            $display("  [FAIL] %0d error(s) -> DO NOT cite this cycle count until fixed.", errors);
        $finish;
    end

    initial begin #500000; $display("  [TIMEOUT] nmark=%0d", nmark); $finish; end
endmodule
