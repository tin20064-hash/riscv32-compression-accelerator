`timescale 1ns/1ps
// ===================================================================
// tb_demo_sparse.v -- VERIFY the board hang bug: SPARSE clk_en
// -------------------------------------------------------------------
// Like tb_demo_pipeline BUT clk_en goes high only once every DIV cycles (like
// the clock-enable on fpga_top). If a compress module is NOT gated by clk_en,
// the 1-cycle done pulse is lost -> dispatcher hangs -> test FAIL/timeout.
// ===================================================================
module tb_demo_sparse;
    localparam N        = 16;
    localparam NUM_BLK  = 3;
    localparam DST_WORD = NUM_BLK * N;
    localparam DIV      = 20;               // clk_en high 1/20 cycles
    // Dia chi word cua mode_log[0]/len_log[0] -- do linker (GCC build) quyet
    // dinh, xem ghi chu chi tiet dau file tb_demo_pipeline.v.
    localparam LEN_BASE  = 0;
    localparam MODE_BASE = 3;

    reg clk = 0, rst_n = 0;
    reg clk_en = 0;
    wire [31:0] debug_data;
    always #5 clk = ~clk;

    // generate sparse clk_en: high 1 cycle every DIV
    integer divcnt = 0;
    always @(posedge clk) begin
        if (!rst_n) begin divcnt <= 0; clk_en <= 0; end
        else begin
            if (divcnt == DIV-1) begin divcnt <= 0; clk_en <= 1; end
            else                 begin divcnt <= divcnt + 1; clk_en <= 0; end
        end
    end

    cpu_top dut (.clk(clk), .rst_n(rst_n), .clk_en(clk_en), .debug_data(debug_data));

    reg [31:0] exp_mode [0:NUM_BLK-1];
    reg [31:0] exp_len  [0:NUM_BLK-1];
    integer i, errors, enpulses;

    // count clk_en pulses elapsed
    always @(posedge clk) if (rst_n && clk_en) enpulses = enpulses + 1;

    initial begin
        exp_mode[0]=0; exp_mode[1]=1; exp_mode[2]=2;
        exp_len[0]=5;  exp_len[1]=5;  exp_len[2]=6;
        enpulses = 0;

        #1;
        $readmemh("demo_pipeline.hex", dut.u_if_stage.u_imem.mem);
        $readmemh("demo_src.hex",      dut.u_scratchpad.mem);

        repeat (4) @(posedge clk);
        rst_n = 1;

        // wait ~800 clk_en pulses (~800 CPU steps as on the board)
        wait (enpulses >= 800);

        errors = 0;
        $display("\n  == tb_demo_sparse (clk_en 1/%0d) sau %0d xung clk_en ==", DIV, enpulses);
        for (i = 0; i < NUM_BLK; i = i + 1) begin
            if (dut.u_mem_stage.data_mem[MODE_BASE+i] !== exp_mode[i]) begin
                errors = errors + 1;
                $display("  [MODE FAIL] block %0d: got=%0d exp=%0d",
                         i, dut.u_mem_stage.data_mem[MODE_BASE+i], exp_mode[i]);
            end else
                $display("  [MODE OK]   block %0d -> mode %0d (len %0d)",
                         i, dut.u_mem_stage.data_mem[MODE_BASE+i], dut.u_mem_stage.data_mem[LEN_BASE+i]);
        end
        $display("");
        if (errors == 0)
            $display("  [PASS] Runs correctly with SPARSE clk_en -> NO hang.");
        else
            $display("  [FAIL] %0d errors -> problem with sparse clk_en.", errors);
        $finish;
    end

    // timeout: if it hangs, we land here
    initial begin
        #2000000;
        $display("\n  [TIMEOUT] -> HUNG with sparse clk_en (as suspected).");
        $display("  data_mem[%0d..%0d] = %0d %0d %0d",
                 MODE_BASE, MODE_BASE+2,
                 dut.u_mem_stage.data_mem[MODE_BASE],
                 dut.u_mem_stage.data_mem[MODE_BASE+1],
                 dut.u_mem_stage.data_mem[MODE_BASE+2]);
        $finish;
    end
endmodule
