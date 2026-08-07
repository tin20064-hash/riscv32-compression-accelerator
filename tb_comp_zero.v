`timescale 1ns/1ps
// ===================================================================
// tb_comp_zero.v -- Self-checking testbench for comp_zero
// -------------------------------------------------------------------
// Flow:
//   1. Nap tb_src_mixed.hex      -> mem[0 .. 4095]  (source)
//   2. Nap tb_expected_zero_mixed.hex -> exp[]       (expected dest)
//   3. Loop over 256 blocks: start -> wait done -> accumulate dest_base
//   4. Compare mem[DEST_BASE + k] with exp[k]; print PASS/FAIL + error count
//
// Run (iverilog):
//   iverilog -o tb comp_zero.v tb_comp_zero.v && vvp tb
// Run (ModelSim):
//   vlog comp_zero.v tb_comp_zero.v
//   vsim -c tb_comp_zero -do "run -all; quit"
// ===================================================================
module tb_comp_zero;
    localparam AW = 13;
    localparam N  = 16;
    localparam MEMSZ     = 8192;
    localparam NUM_BLK   = 256;        // 4096 word / 16
    localparam SRC_BASE  = 0;
    localparam DEST_BASE = 4096;       // dest starts right after src
    localparam EXP_LEN   = 3216;       // expected dest word count (mixed)

    reg clk = 0, rst_n = 0;
    always #5 clk = ~clk;              // 100 MHz

    // ---- behavioral memory: 1R1W, async read, sync write (like scratchpad.v) ----
    reg  [31:0] mem [0:MEMSZ-1];
    reg  [31:0] exp [0:EXP_LEN-1];

    // signals wired to the DUT
    reg          start;
    reg  [AW-1:0] src_base, dest_base;
    wire [AW-1:0] rd_addr;
    wire [31:0]   rd_data;
    wire          wr_en;
    wire [AW-1:0] wr_addr;
    wire [31:0]   wr_data;
    wire          busy, done;
    wire [AW:0]   out_len;

    assign rd_data = mem[rd_addr];     // async read
    always @(posedge clk)
        if (wr_en) mem[wr_addr] <= wr_data;   // sync write

    comp_zero #(.AW(AW), .N(N)) dut (
        .clk(clk), .rst_n(rst_n), .clk_en(1'b1),
        .start(start), .src_base(src_base), .dest_base(dest_base),
        .rd_addr(rd_addr), .rd_data(rd_data),
        .wr_en(wr_en), .wr_addr(wr_addr), .wr_data(wr_data),
        .busy(busy), .done(done), .out_len(out_len)
    );

    integer b, k, errors;
    reg [AW-1:0] cur_dest;
    reg [AW:0]   blk_len;

    // run 1 block, return length via blk_len
    task run_block(input [AW-1:0] sb, input [AW-1:0] db);
    begin
        @(posedge clk);
        start <= 1'b1; src_base <= sb; dest_base <= db;
        @(posedge clk);
        start <= 1'b0;
        while (!done) @(posedge clk);   // wait until done
        blk_len = out_len;              // out_len valid on the same cycle as done
    end
    endtask

    initial begin
        // load data
        for (k=0;k<MEMSZ;k=k+1) mem[k]=32'b0;
        $readmemh("tb_src_mixed.hex", mem, SRC_BASE);
        $readmemh("tb_expected_zero_mixed.hex", exp);

        // diagnostic: count non-zero words in source. If 0, the file was NOT loaded.
        begin : diag
            integer nz, j;
            nz = 0;
            for (j = 0; j < NUM_BLK*N; j = j + 1)
                if (mem[SRC_BASE+j] != 32'b0) nz = nz + 1;
            $display("  [load] non-zero words in source = %0d (must be > 0) | exp[0]=%08h",
                     nz, exp[0]);
        end

        start=0; src_base=0; dest_base=0; errors=0;
        repeat(3) @(posedge clk);
        rst_n=1;
        @(posedge clk);

        // xu ly tung block, pack dest lien tiep tu DEST_BASE
        cur_dest = DEST_BASE;
        for (b=0; b<NUM_BLK; b=b+1) begin
            run_block(b*N, cur_dest);
            cur_dest = cur_dest + blk_len[AW-1:0];
        end

        // compare dest with expected
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
            $display("  [PASS] comp_zero matches golden model over all %0d blocks.", NUM_BLK);
        else
            $display("  [FAIL] so loi = %0d", errors);
        $finish;
    end

    // anti-hang
    initial begin #2000000; $display("  [TIMEOUT]"); $finish; end
endmodule
