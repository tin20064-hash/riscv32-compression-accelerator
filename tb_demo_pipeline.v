`timescale 1ns/1ps
// ===================================================================
// tb_demo_pipeline.v -- Phase 3.2: run the detect->select->compress loop on the CORE
// -------------------------------------------------------------------
// Nap demo_pipeline.hex vao instruction memory, demo_src.hex vao scratchpad,
// run the program, then:
//   - check data_mem[MODE_BASE+i] == detector-selected mode  (expected [ZERO,RLE,DELTA])
//   - check data_mem[LEN_BASE+i]  == out_len                 (expected [5,5,6])
//   - check dest scratchpad [48..] == demo_expected_dest.hex
//
// MODE_BASE/LEN_BASE: dia chi (word) cua 2 bien toan cuc mode_log[]/len_log[]
// trong demo_pipeline.c. Dia chi nay do LINKER (link.ld + trinh tu bien trong
// file .c) quyet dinh -- KHONG co dia chi co dinh nhu quy uoc code asm cu
// (asm_riscv.py, dung word 0-2 cho mode va word 16-18 cho len). Neu build lai
// bang GCC (make CROSS=... clean all) va sua/them bien toan cuc trong
// demo_pipeline.c, dia chi co the doi -- luc do phai chay lai:
//   nm demo_pipeline.elf | grep -E "mode_log|len_log"
// roi cap nhat 2 localparam ben duoi cho khop (dia chi byte tu nm chia 4 =
// dia chi word). Gia tri hien tai (LEN_BASE=0, MODE_BASE=3) ung voi ban
// build GCC hien tai: len_log tai byte 0x00 (word 0), mode_log tai byte
// 0x0c (word 3).
//
// Run (ModelSim):
//   vlog <tat ca .v cpu> tb_demo_pipeline.v
//   vsim -c tb_demo_pipeline -do "run -all; quit -f"
// ===================================================================
module tb_demo_pipeline;
    localparam N        = 16;
    localparam NUM_BLK  = 3;
    localparam DST_WORD = NUM_BLK * N;     // 48
    localparam EXP_DLEN = 16;              // total compressed words (5+5+6)
    localparam LEN_BASE  = 0;              // dia chi word cua len_log[0]  (xem ghi chu tren dau file)
    localparam MODE_BASE = 3;              // dia chi word cua mode_log[0] (xem ghi chu tren dau file)

    reg clk = 0, rst_n = 0, clk_en = 1;
    wire [31:0] debug_data;
    always #5 clk = ~clk;

    cpu_top dut (.clk(clk), .rst_n(rst_n), .clk_en(clk_en), .debug_data(debug_data));

    reg [31:0] exp_dest [0:EXP_DLEN-1];
    reg [31:0] exp_mode [0:NUM_BLK-1];
    reg [31:0] exp_len  [0:NUM_BLK-1];

    integer i, k, errors;

    initial begin
        // expected: detector picks ZERO,RLE,DELTA for 3 contrasting blocks
        exp_mode[0]=0; exp_mode[1]=1; exp_mode[2]=2;
        exp_len[0]=5;  exp_len[1]=5;  exp_len[2]=6;
        $readmemh("demo_expected_dest.hex", exp_dest);

        // override memory after the modules' initial blocks have run
        #1;
        $readmemh("demo_pipeline.hex", dut.u_if_stage.u_imem.mem);   // chuong trinh
        $readmemh("demo_src.hex",      dut.u_scratchpad.mem);        // source -> words 0..47

        // reset then run
        repeat (4) @(posedge clk);
        rst_n = 1;

        // enough time for 3 blocks (detect+poll+compress+poll ~60-80 cycles each)
        repeat (600) @(posedge clk);

        // ---- check ----
        errors = 0;
        $display("\n  == demo_pipeline result on the core ==");
        for (i = 0; i < NUM_BLK; i = i + 1) begin
            if (dut.u_mem_stage.data_mem[MODE_BASE+i] !== exp_mode[i]) begin
                errors = errors + 1;
                $display("  [MODE FAIL] block %0d: got=%0d exp=%0d",
                         i, dut.u_mem_stage.data_mem[MODE_BASE+i], exp_mode[i]);
            end else
                $display("  [MODE OK]   block %0d -> mode %0d", i, dut.u_mem_stage.data_mem[MODE_BASE+i]);

            if (dut.u_mem_stage.data_mem[LEN_BASE+i] !== exp_len[i]) begin
                errors = errors + 1;
                $display("  [LEN  FAIL] block %0d: got=%0d exp=%0d",
                         i, dut.u_mem_stage.data_mem[LEN_BASE+i], exp_len[i]);
            end
        end

        for (k = 0; k < EXP_DLEN; k = k + 1) begin
            if (dut.u_scratchpad.mem[DST_WORD+k] !== exp_dest[k]) begin
                errors = errors + 1;
                if (errors <= 8)
                    $display("  [DEST FAIL] dest[%0d] (word %0d): got=%08h exp=%08h",
                             k, DST_WORD+k, dut.u_scratchpad.mem[DST_WORD+k], exp_dest[k]);
            end
        end

        $display("");
        if (errors == 0)
            $display("  [PASS] HW/SW detect->select->compress loop runs correctly on the core (3 blocks, 3 modes).");
        else
            $display("  [FAIL] so loi = %0d", errors);
        $finish;
    end

    initial begin #200000; $display("  [TIMEOUT]"); $finish; end
endmodule
