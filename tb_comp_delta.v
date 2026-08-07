`timescale 1ns/1ps
// ===================================================================
// tb_comp_delta.v -- Self-checking testbench for comp_delta
// -------------------------------------------------------------------
//   1. Nap tb_src_mixed.hex             -> mem[0..4095]  (source)
//   2. Nap tb_expected_delta_mixed.hex  -> exp[]         (expected dest)
//   3. Loop over 256 blocks: start -> wait done -> accumulate dest_base
//   4. Compare mem[DEST_BASE+k] with exp[k]; print PASS/FAIL
//
// Run (iverilog):
//   iverilog -o tb_delta comp_delta.v tb_comp_delta.v && vvp tb_delta
// Run (ModelSim):
//   vlog comp_delta.v tb_comp_delta.v
//   vsim -c tb_comp_delta -do "run -all; quit"
// ===================================================================
module tb_comp_delta;
    localparam AW = 13;
    localparam N  = 16;
    localparam MEMSZ     = 16384;
    localparam NUM_BLK   = 256;
    localparam SRC_BASE  = 0;
    localparam DEST_BASE = 4096;
    localparam EXP_LEN   = 2526;        // tu golden_compress.py (mode delta)

    reg clk = 0, rst_n = 0;
    always #5 clk = ~clk;

    reg  [31:0] mem [0:MEMSZ-1];
    reg  [31:0] exp [0:EXP_LEN-1];

    reg          start;
    reg  [AW-1:0] src_base, dest_base;
    wire [AW-1:0] rd_addr;
    wire [31:0]   rd_data;
    wire          wr_en;
    wire [AW-1:0] wr_addr;
    wire [31:0]   wr_data;
    wire          busy, done;
    wire [AW:0]   out_len;

    assign rd_data = mem[rd_addr];
    always @(posedge clk)
        if (wr_en) mem[wr_addr] <= wr_data;

    comp_delta #(.AW(AW), .N(N)) dut (
        .clk(clk), .rst_n(rst_n), .clk_en(1'b1),
        .start(start), .src_base(src_base), .dest_base(dest_base),
        .rd_addr(rd_addr), .rd_data(rd_data),
        .wr_en(wr_en), .wr_addr(wr_addr), .wr_data(wr_data),
        .busy(busy), .done(done), .out_len(out_len)
    );

    integer b, k, errors;
    reg [AW-1:0] cur_dest;
    reg [AW:0]   blk_len;

    task run_block(input [AW-1:0] sb, input [AW-1:0] db);
    begin
        @(posedge clk);
        start <= 1'b1; src_base <= sb; dest_base <= db;
        @(posedge clk);
        start <= 1'b0;
        while (!done) @(posedge clk);
        blk_len = out_len;
    end
    endtask

    initial begin
        for (k=0;k<MEMSZ;k=k+1) mem[k]=32'b0;
        $readmemh("tb_src_mixed.hex", mem, SRC_BASE);
        $readmemh("tb_expected_delta_mixed.hex", exp);

        start=0; src_base=0; dest_base=0; errors=0;
        repeat(3) @(posedge clk);
        rst_n=1;
        @(posedge clk);

        cur_dest = DEST_BASE;
        for (b=0; b<NUM_BLK; b=b+1) begin
            run_block(b*N, cur_dest);
            cur_dest = cur_dest + blk_len[AW-1:0];
        end

        for (k=0; k<EXP_LEN; k=k+1) begin
            if (mem[DEST_BASE+k] !== exp[k]) begin
                errors = errors + 1;
                if (errors <= 5)
                    $display("  [MISMATCH] dest[%0d]: got=%08h exp=%08h",
                             k, mem[DEST_BASE+k], exp[k]);
            end
        end

        $display("");
        $display("  Total dest words written : %0d (expected %0d)", cur_dest-DEST_BASE, EXP_LEN);
        if ((cur_dest-DEST_BASE)==EXP_LEN && errors==0)
            $display("  [PASS] comp_delta matches golden model over all %0d blocks.", NUM_BLK);
        else
            $display("  [FAIL] so loi = %0d", errors);
        $finish;
    end

    initial begin #5000000; $display("  [TIMEOUT]"); $finish; end
endmodule
