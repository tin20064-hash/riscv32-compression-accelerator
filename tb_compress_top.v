`timescale 1ns/1ps
// ===================================================================
// tb_compress_top.v -- Phase 4.1: testbench auto-comparing against golden
// -------------------------------------------------------------------
// Unlike tb_comp_zero/rle/delta (each MODULE separately), this tests
// CA DUONG DISPATCHER THAT: drive compress_accel qua custom instruction CCOMPR
//   (custom_en=1, custom_op=001, op_a=src_byte, op_b=dst_byte|mode)
// all 3 MODES, comparing each compressed word with golden tb_expected_<mode>_mixed.hex,
// bao PASS/FAIL toan bo 256 blocks.
//
// Day la evidence that "RTL compress == golden model" as required by Q2 reviewers (4.1),
// run through the exact mechanism the CPU uses (CCOMPR + poll CSTAT done + out_len).
//
// Run (ModelSim):
//   vlog comp_zero.v comp_rle.v comp_delta.v pattern_detect.v Compress_accel.v tb_compress_top.v
//   vsim -c tb_compress_top -do "run -all; quit -f"
// ===================================================================
module tb_compress_top;
    localparam AW      = 14;            // 16384 word: du chua src(4096)+rle_dest(4318)
    localparam N       = 16;
    localparam MEMSZ   = (1 << AW);
    localparam NUM_BLK = 256;
    localparam SRC_BASE  = 0;
    localparam DEST_BASE = 4096;        // dest starts right after src

    // funct3 custom + mode tag
    localparam [2:0] CCOMPR = 3'b001;
    localparam [1:0] M_ZERO = 2'b00, M_RLE = 2'b01, M_DELTA = 2'b10;

    reg clk = 0, rst_n = 0;
    always #5 clk = ~clk;               // 100 MHz

    // ---- behavioral scratchpad: async read, sync write (like scratchpad.v) ----
    reg [31:0] mem [0:MEMSZ-1];

    // ---- driver custom instruction ----
    reg         custom_en;
    reg  [2:0]  custom_op;
    reg  [31:0] op_a, op_b;

    wire [AW-1:0] spad_raddr;
    wire [31:0]   spad_rdata;
    wire          spad_we;
    wire [AW-1:0] spad_waddr;
    wire [31:0]   spad_wdata;
    wire [31:0]   result;
    wire          busy, done;

    assign spad_rdata = mem[spad_raddr];
    always @(posedge clk)
        if (spad_we) mem[spad_waddr] <= spad_wdata;

    compress_accel #(.AW(AW), .N(N)) dut (
        .clk(clk), .rst_n(rst_n), .clk_en(1'b1),
        .custom_en(custom_en), .custom_op(custom_op),
        .op_a(op_a), .op_b(op_b),
        .spad_raddr(spad_raddr), .spad_rdata(spad_rdata),
        .spad_we(spad_we), .spad_waddr(spad_waddr), .spad_wdata(spad_wdata),
        .result(result), .busy(busy), .done(done)
    );

    // ---- golden memory + counters ----
    reg  [31:0]   exp [0:5119];          // du chua EXP_LEN lon nhat (rle=4318)
    integer       b, k, errors, total_err;
    reg  [AW-1:0] cur_dest;
    reg  [AW:0]   blk_len;

    // compress 1 block via CCOMPR; get out_len via last_result (poll done)
    task run_block(input [1:0] mode, input [AW-1:0] sb, input [AW-1:0] db);
    begin
        @(posedge clk);
        custom_en <= 1'b1;
        custom_op <= CCOMPR;
        op_a      <= sb << 2;                  // source byte addr
        op_b      <= (db << 2) | {30'b0, mode};// dest byte addr | mode in [1:0]
        @(posedge clk);
        custom_en <= 1'b0;
        // Poll on busy (=state S_RUN). Use #1 to read the COMMITTED value after NBA,
        // avoid race: compress_accel's done_r stays high until the next command (unlike a
        // standalone module -> cannot poll 'done' right after @(posedge) since it reads the
        // previous block's stale value).
        @(posedge clk); #1;                    // FSM da vao S_RUN -> busy=1
        while (busy) begin @(posedge clk); #1; end
        blk_len = dut.last_result[AW:0];        // out_len = last_result (last_op=0)
    end
    endtask

    // run a whole mode: 256 blocks, pack dest contiguously, compare with golden
    task run_mode(input [1:0] mode, input [8*48:1] fname, input integer exp_len);
    begin
        // load golden for this mode
        for (k = 0; k < 5120; k = k + 1) exp[k] = 32'b0;
        $readmemh(fname, exp);
        // xoa vung dest
        for (k = DEST_BASE; k < MEMSZ; k = k + 1) mem[k] = 32'b0;

        cur_dest = DEST_BASE;
        for (b = 0; b < NUM_BLK; b = b + 1) begin
            run_block(mode, b * N, cur_dest);
            cur_dest = cur_dest + blk_len[AW-1:0];
        end

        errors = 0;
        for (k = 0; k < exp_len; k = k + 1) begin
            if (mem[DEST_BASE + k] !== exp[k]) begin
                errors = errors + 1;
                if (errors <= 4)
                    $display("    [MISMATCH] dest[%0d]: got=%08h exp=%08h",
                             k, mem[DEST_BASE + k], exp[k]);
            end
        end

        if ((cur_dest - DEST_BASE) == exp_len && errors == 0)
            $display("  [PASS] mode %0d: %0d block, %0d word == golden.",
                     mode, NUM_BLK, exp_len);
        else begin
            $display("  [FAIL] mode %0d: wrote %0d words (golden %0d), errors=%0d",
                     mode, cur_dest - DEST_BASE, exp_len, errors);
            total_err = total_err + (errors == 0 ? 1 : errors);
        end
    end
    endtask

    initial begin
        // load source
        for (k = 0; k < MEMSZ; k = k + 1) mem[k] = 32'b0;
        $readmemh("tb_src_mixed.hex", mem, SRC_BASE);

        custom_en = 0; custom_op = 0; op_a = 0; op_b = 0; total_err = 0;
        repeat (3) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        $display("\n  == Phase 4.1: compress_accel dispatcher vs golden model ==");
        run_mode(M_ZERO,  "tb_expected_zero_mixed.hex",  3216);
        run_mode(M_RLE,   "tb_expected_rle_mixed.hex",   4318);
        run_mode(M_DELTA, "tb_expected_delta_mixed.hex", 2526);

        $display("");
        if (total_err == 0)
            $display("  [PASS] RTL compress (via CCOMPR dispatcher) == golden for all 3 modes, %0d blocks.",
                     NUM_BLK);
        else
            $display("  [FAIL] tong loi = %0d", total_err);
        $finish;
    end

    initial begin #5000000; $display("  [TIMEOUT]"); $finish; end
endmodule
