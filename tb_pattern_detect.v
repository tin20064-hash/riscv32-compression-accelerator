`timescale 1ns/1ps
// ===================================================================
// tb_pattern_detect.v -- Self-checking testbench for pattern_detect
// -------------------------------------------------------------------
//   1. Nap tb_src_mixed.hex             -> mem[0..4095]
//   2. Nap tb_expected_detect_mixed.hex -> exp[] (256 det_word)
//   3. Loop 256 blocks: start -> wait done -> grab det_word
//   4. Compare det_word with golden; print PASS/FAIL
//
// Threshold MUST match golden_compress.py: TAU1=TAU2=WMAX=8.
//
// Run (ModelSim):
//   vlog pattern_detect.v tb_pattern_detect.v
//   vsim -c tb_pattern_detect -do "run -all; quit -f"
// ===================================================================
module tb_pattern_detect;
    localparam AW = 13;
    localparam N  = 16;
    localparam MEMSZ   = 8192;
    localparam NUM_BLK = 256;
    localparam [5:0] TAU1 = 6'd8, TAU2 = 6'd8, WMAX = 6'd8;

    reg clk = 0, rst_n = 0;
    always #5 clk = ~clk;

    reg  [31:0] mem [0:MEMSZ-1];
    reg  [31:0] exp [0:NUM_BLK-1];

    reg          start;
    reg  [AW-1:0] src_base;
    wire [AW-1:0] rd_addr;
    wire [31:0]   rd_data;
    wire          busy, done;
    wire [1:0]    mode;
    wire [31:0]   det_word;

    assign rd_data = mem[rd_addr];

    pattern_detect #(.AW(AW), .N(N)) dut (
        .clk(clk), .rst_n(rst_n), .clk_en(1'b1),
        .start(start), .src_base(src_base),
        .rd_addr(rd_addr), .rd_data(rd_data),
        .busy(busy), .done(done), .mode(mode), .det_word(det_word)
    );

    integer b, k, errors;
    reg [31:0] got;

    task run_block(input [AW-1:0] sb);
    begin
        @(posedge clk);
        start <= 1'b1; src_base <= sb;
        @(posedge clk);
        start <= 1'b0;
        while (!done) @(posedge clk);
        got = det_word;
    end
    endtask

    initial begin
        for (k=0;k<MEMSZ;k=k+1) mem[k]=32'b0;
        $readmemh("tb_src_mixed.hex", mem, 0);
        $readmemh("tb_expected_detect_mixed.hex", exp);

        start=0; src_base=0; errors=0;
        repeat(3) @(posedge clk);
        rst_n=1;
        @(posedge clk);

        for (b=0; b<NUM_BLK; b=b+1) begin
            run_block(b*N);
            if (got !== exp[b]) begin
                errors = errors + 1;
                if (errors <= 5)
                    $display("  [MISMATCH] block %0d: got=%08h exp=%08h (mode got=%0d exp=%0d)",
                             b, got, exp[b], got[1:0], exp[b][1:0]);
            end
        end

        $display("");
        if (errors==0)
            $display("  [PASS] pattern_detect matches golden over all %0d blocks.", NUM_BLK);
        else
            $display("  [FAIL] so loi = %0d / %0d block", errors, NUM_BLK);
        $finish;
    end

    initial begin #3000000; $display("  [TIMEOUT]"); $finish; end
endmodule
