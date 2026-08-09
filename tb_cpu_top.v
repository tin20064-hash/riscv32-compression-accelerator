`timescale 1ns/1ps

module tb_cpu_top;

     reg        clk   = 0;
    reg        rst_n = 0;
    reg        clk_en;        
    wire [31:0] debug_data;   

    always #5 clk = ~clk;

     cpu_top dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .clk_en     (clk_en),
        .debug_data (debug_data)
    );

    `define REGFILE dut.u_id_stage.regfile
    `define DMEM    dut.u_mem_stage.data_mem

    integer pass_cnt, fail_cnt;

    task check_reg;
        input [4:0]   regno;
        input [31:0]  expected;
        input [255:0] label;
        begin
            if (`REGFILE[regno] !== expected) begin
                $display("FAIL [%0s]  x%0d = 0x%08X  (exp 0x%08X)",
                         label, regno, `REGFILE[regno], expected);
                fail_cnt = fail_cnt + 1;
            end else begin
                $display("PASS [%0s]  x%0d = 0x%08X", label, regno, expected);
                pass_cnt = pass_cnt + 1;
            end
        end
    endtask

    task check_mem;
        input [7:0]   widx;
        input [31:0]  expected;
        input [255:0] label;
        begin
            if (`DMEM[widx] !== expected) begin
                $display("FAIL [%0s]  mem[%0d] = 0x%08X  (exp 0x%08X)",
                         label, widx, `DMEM[widx], expected);
                fail_cnt = fail_cnt + 1;
            end else begin
                $display("PASS [%0s]  mem[%0d] = 0x%08X", label, widx, expected);
                pass_cnt = pass_cnt + 1;
            end
        end
    endtask

    integer en_cnt;
    initial en_cnt = 0;

    always @(posedge clk) begin
        if (!rst_n) begin
            clk_en <= 1'b0;
            en_cnt <= 0;
        end else begin
            if (en_cnt == 9) begin
                clk_en <= 1'b1;
                en_cnt <= 0;
            end else begin
                clk_en <= 1'b0;
                en_cnt <= en_cnt + 1;
            end
        end
    end

    always @(posedge clk) begin
        if (rst_n && clk_en)
            $display("[T=%0t ns]  debug_data = 0x%08X", $time, debug_data);
    end

        initial begin
        $dumpfile("cpu_wave.vcd");
        $dumpvars(0, tb_cpu_top);

        pass_cnt = 0;
        fail_cnt = 0;

        @(posedge clk); #1; rst_n = 0;
        repeat(4) @(posedge clk);
        rst_n = 1;

        begin : wait_loop
            integer cpu_ticks;
            cpu_ticks = 0;
            while (cpu_ticks < 200) begin
                @(posedge clk);
                if (clk_en) cpu_ticks = cpu_ticks + 1;
            end
        end
        $display("");
        $display("============ FULL PROGRAM TEST ============");
        $display("--- Registers (ALU / shift / logic / forwarding / loads / jumps) ---");

        check_reg( 3, 32'h00000007, "x3_ADD_fwd_chain"  );
        check_reg( 5, 32'h0000000E, "x5_ADD_chain_end"  );
        check_reg( 6, 32'h00000009, "x6_SUB"            );
        check_reg( 7, 32'h0000000B, "x7_OR"             );
        check_reg( 8, 32'h00000002, "x8_XOR"            );
        check_reg( 9, 32'h00000002, "x9_AND_fwd"        );
        check_reg(10, 32'hFFFFFFF9, "x10_ADDI_neg"      );
        check_reg(11, 32'h00000001, "x11_SLTI"          );
        check_reg(12, 32'h00000000, "x12_SLTIU"         );
        check_reg(13, 32'h00000002, "x13_ANDI"          );
        check_reg(14, 32'h00000050, "x14_SLLI"          );
        check_reg(15, 32'hFFFFFFFC, "x15_SRAI"          );
        check_reg(16, 32'h0000000F, "x16_SRLI"          );
        check_reg(17, 32'h00000000, "x17_SLT"           );
        check_reg(18, 32'h00000001, "x18_SLTU"          );
        check_reg(19, 32'h0000007B, "x19_LW"            );
        check_reg(20, 32'h0000004E, "x20_LoadUse_stall" );
        check_reg(21, 32'hFFFFFFFF, "x21_LB_signext"    );
        check_reg(22, 32'h000000FF, "x22_LBU"           );
        check_reg(23, 32'hFFFF8000, "x23_LH_signext"    );
        check_reg(24, 32'h00008000, "x24_LHU"           );
        check_reg(26, 32'h000000A4, "x26_JAL_retaddr"   );
        check_reg(27, 32'h0000002A, "x27_JAL_func_body" );
        check_reg(28, 32'h00000007, "x28_JALR_return"   );
        check_reg(29, 32'h00008000, "x29_LUI"           );
        check_reg(30, 32'h000000B8, "x30_AUIPC"         );

        $display("--- Memory (store sizes + branch flags) ---");

        check_mem( 0, 32'h00000005, "mem0_SW_word"      );
        check_mem( 8, 32'h000000FF, "mem8_SB_byte"      );
        check_mem( 9, 32'h00008000, "mem9_SH_half"      );
        check_mem(16, 32'h00000000, "mem16_BEQ_taken"   );
        check_mem(17, 32'h00000000, "mem17_BNE_taken"   );
        check_mem(18, 32'h00000000, "mem18_BLT_taken"   );
        check_mem(19, 32'h00000001, "mem19_BGE_nottaken");
        check_mem(20, 32'h00000001, "mem20_BLTU_nottaken");
        check_mem(21, 32'h00000000, "mem21_BGEU_taken"  );
        check_mem(22, 32'h00000001, "mem22_BLT_nottaken");
        check_mem(23, 32'h00000000, "mem23_BGE_taken"   );

        $display("===========================================");
        $display("Total: %0d PASS, %0d FAIL", pass_cnt, fail_cnt);
        if (fail_cnt == 0)
            $display("** ALL TESTS PASSED **");
        else
            $display("** %0d TEST(S) FAILED **", fail_cnt);

        $finish;
    end

    initial begin
        #100_000;
        $display("[TIMEOUT] Simulation exceeded 100us ? aborting.");
        $finish;
    end

endmodule
