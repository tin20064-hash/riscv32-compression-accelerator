`timescale 1ns/1ps
// ===================================================================
// tb_throughput.v -- Phase 6.1: MEASURE cycle-accurate THROUGHPUT (RTL)
// -------------------------------------------------------------------
// Count REAL hardware cycles for:
//   - PDETECT (detect 1 block)
//   - CCOMPR each mode (ZERO/RLE/DELTA) on a representative block per dataset
// then derive:
//   - latency/op (cycle)
//   - end-to-end/block = detect + compress
//   - throughput = 64 byte vao / so cycle  (bytes/cycle)
//
// This is HARDWARE DATA measured by sim (not an estimate), complementing
// the Phase-6.1 baseline table. Energy/byte = power x time needs Vivado -> Phase 5.
//
// Run (ModelSim):
//   vlog comp_zero.v comp_rle.v comp_delta.v pattern_detect.v Compress_accel.v tb_throughput.v
//   vsim -c tb_throughput -do "run -all; quit -f"
// ===================================================================
module tb_throughput;
    localparam AW = 14;
    localparam N  = 16;
    localparam MEMSZ = (1 << AW);
    localparam [2:0] PDETECT = 3'b000, CCOMPR = 3'b001;
    localparam [1:0] M_ZERO = 2'b00, M_RLE = 2'b01, M_DELTA = 2'b10;
    localparam SRC = 0, DST = 1024;     // block dai dien o word 0..15, dest o 1024

    reg clk = 0, rst_n = 0;
    always #5 clk = ~clk;

    reg [31:0] mem [0:MEMSZ-1];

    reg         custom_en;
    reg  [2:0]  custom_op;
    reg  [31:0] op_a, op_b;
    wire [AW-1:0] spad_raddr, spad_waddr;
    wire [31:0]   spad_rdata, spad_wdata;
    wire          spad_we, busy, done;
    wire [31:0]   result;

    assign spad_rdata = mem[spad_raddr];
    always @(posedge clk) if (spad_we) mem[spad_waddr] <= spad_wdata;

    compress_accel #(.AW(AW), .N(N)) dut (
        .clk(clk), .rst_n(rst_n), .clk_en(1'b1),
        .custom_en(custom_en), .custom_op(custom_op),
        .op_a(op_a), .op_b(op_b),
        .spad_raddr(spad_raddr), .spad_rdata(spad_rdata),
        .spad_we(spad_we), .spad_waddr(spad_waddr), .spad_wdata(spad_wdata),
        .result(result), .busy(busy), .done(done)
    );

    integer lat, k;
    integer det_lat, lat_z, lat_r, lat_d;
    integer olen_z, olen_r, olen_d;

    // measure 'busy' cycles (= S_RUN) for one custom instruction
    task measure(input [2:0] op, input [1:0] mode, output integer lat_o, output integer olen_o);
    begin
        @(posedge clk);
        custom_en <= 1'b1; custom_op <= op;
        op_a <= SRC << 2;
        op_b <= (op == CCOMPR) ? ((DST << 2) | {30'b0, mode}) : 32'b0;
        @(posedge clk);
        custom_en <= 1'b0;
        lat_o = 0;
        @(posedge clk); #1;                       // FSM da vao S_RUN
        while (busy) begin lat_o = lat_o + 1; @(posedge clk); #1; end
        olen_o = dut.last_result[15:0];           // out_len (or det_word for detect)
    end
    endtask

    initial begin
        for (k = 0; k < MEMSZ; k = k + 1) mem[k] = 32'b0;
        custom_en = 0; custom_op = 0; op_a = 0; op_b = 0;
        repeat (3) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        // ----- DETECT (data-independent latency): use zero_heavy block -----
        $readmemh("dataset_zero_heavy.hex", mem, SRC);
        measure(PDETECT, M_ZERO, det_lat, olen_z);

        // ----- COMPRESS each mode on a representative block from its dataset -----
        $readmemh("dataset_zero_heavy.hex", mem, SRC);
        measure(CCOMPR, M_ZERO, lat_z, olen_z);

        $readmemh("dataset_repetitive.hex", mem, SRC);
        measure(CCOMPR, M_RLE, lat_r, olen_r);

        $readmemh("dataset_slow_varying.hex", mem, SRC);
        measure(CCOMPR, M_DELTA, lat_d, olen_d);

        // ----- bao cao -----
        $display("\n  == Phase 6.1: Cycle-accurate throughput (RTL sim, N=%0d, 64 bytes/block) ==\n", N);
        $display("  PDETECT latency            = %0d cycle (data-independent ~ N+2)", det_lat);
        $display("");
        $display("  %-10s %-10s %-10s %-14s", "mode", "compress", "out_len", "byte_out");
        $display("  %-10s %-10s %-10s %-14s", "----", "cycle", "word", "byte");
        $display("  %-10s %-10d %-10d %-14d", "ZERO",  lat_z, olen_z, olen_z*4);
        $display("  %-10s %-10d %-10d %-14d", "RLE",   lat_r, olen_r, olen_r*4);
        $display("  %-10s %-10d %-10d %-14d", "DELTA", lat_d, olen_d, olen_d*4);
        $display("");
        $display("  End-to-end/block (detect+compress) & throughput (byte vao / cycle):");
        report("ZERO",  det_lat, lat_z);
        report("RLE",   det_lat, lat_r);
        report("DELTA", det_lat, lat_d);
        $display("");
        $display("  [DONE] Throughput measured from RTL. Energy/byte -> Phase 5 (Vivado power).");
        $finish;
    end

    // in end-to-end + throughput (nhan 1000 de lay 3 chu so thap phan vi Verilog integer)
    task report(input [8*8:1] nm, input integer dl, input integer cl);
        integer total; integer thr_milli;
    begin
        total = dl + cl;
        thr_milli = (64 * 1000) / total;          // byte/cycle x1000
        $display("    %-8s detect=%0d + compress=%0d = %0d cycle -> %0d.%03d byte/cycle",
                 nm, dl, cl, total, thr_milli/1000, thr_milli%1000);
    end
    endtask

    initial begin #2000000; $display("  [TIMEOUT]"); $finish; end
endmodule
