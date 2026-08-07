`timescale 1ns/1ps

module tb_ex_stage;

reg  [31:0] alu_in1, alu_in2;
reg  [3:0]  alu_ctrl;
reg  [31:0] pc_ex, imm_ex;
reg         branch, jump;
reg         alu_opA_sel, jalr_sel;
reg  [2:0]  funct3_ex;

wire [31:0] result;
wire        zero, pc_src;
wire [31:0] branch_target;

ex_stage dut (
    .alu_in1       (alu_in1),
    .alu_in2       (alu_in2),
    .alu_ctrl      (alu_ctrl),
    .pc_ex         (pc_ex),
    .imm_ex        (imm_ex),
    .branch        (branch),
    .jump          (jump),
    .alu_opA_sel   (alu_opA_sel),
    .jalr_sel      (jalr_sel),
    .funct3_ex     (funct3_ex),
    .result        (result),
    .zero          (zero),
    .pc_src        (pc_src),
    .branch_target (branch_target)
);

integer pass_cnt, fail_cnt;

task check32;
    input [31:0] exp_result;
    input        exp_zero, exp_pc_src;
    input [127:0] label;
    begin
        if (result !== exp_result || zero !== exp_zero || pc_src !== exp_pc_src) begin
            $display("FAIL [%0s] result=%08X(exp %08X) z=%b(exp %b) pcsrc=%b(exp %b)",
                label, result, exp_result, zero, exp_zero, pc_src, exp_pc_src);
            fail_cnt = fail_cnt + 1;
        end else begin
            $display("PASS [%0s] result=%08X", label, result);
            pass_cnt = pass_cnt + 1;
        end
    end
endtask

initial begin
    branch = 0; jump = 0; pc_ex = 32'h20; imm_ex = 32'h8;
    alu_opA_sel = 0; jalr_sel = 0; funct3_ex = 3'b000;
    pass_cnt = 0; fail_cnt = 0;
    #2;
    
    $display("--- EX Stage Tests ---");
    
    alu_in1=32'd5; alu_in2=32'd3; alu_ctrl=4'b0000; #2;
    check32(32'd8, 0, 0, "T1_ADD");
    
    alu_in1=32'd5; alu_in2=32'd5; alu_ctrl=4'b0001; #2;
    check32(32'd0, 1, 0, "T2_SUB_zero");
    
    branch=1; funct3_ex=3'b000; alu_in1=32'd7; alu_in2=32'd7; alu_ctrl=4'b0001; #2;
    check32(32'd0, 1, 1, "T3_BEQ_taken");
    if (branch_target !== 32'h28) begin
        $display("FAIL T3 branch_target: got %08X exp 0x28", branch_target);
        fail_cnt = fail_cnt + 1;
    end else
        $display("PASS T3 branch_target=0x28");
        
    branch=1; funct3_ex=3'b000; alu_in1=32'd3; alu_in2=32'd7; alu_ctrl=4'b0001; #2;
    check32(32'hFFFFFFFC, 0, 0, "T4_BEQ_notTaken");
    
    branch=0; alu_in1=32'hF0; alu_in2=32'hFF; alu_ctrl=4'b0010; #2;
    check32(32'hF0, 0, 0, "T5_AND");
    
    alu_in1=32'hF0; alu_in2=32'h0F; alu_ctrl=4'b0011; #2;
    check32(32'hFF, 0, 0, "T6_OR");
    
    alu_in1=32'hAA; alu_in2=32'hFF; alu_ctrl=4'b0100; #2;
    check32(32'h55, 0, 0, "T7_XOR");
    
    alu_in1=32'd1; alu_in2=32'd4; alu_ctrl=4'b0101; #2;
    check32(32'd16, 0, 0, "T8_SLL");
    
    alu_in1=32'd16; alu_in2=32'd2; alu_ctrl=4'b0110; #2;
    check32(32'd4, 0, 0, "T9_SRL");
    
    alu_in1=32'hFFFFFFF8; alu_in2=32'd1; alu_ctrl=4'b0111; #2;
    check32(32'hFFFFFFFC, 0, 0, "T10_SRA");
    
    alu_in1=32'd3; alu_in2=32'd5; alu_ctrl=4'b1000; #2;
    check32(32'd1, 0, 0, "T11_SLT");
    
    alu_in1=32'd5; alu_in2=32'd3; alu_ctrl=4'b1000; #2;
    check32(32'd0, 1, 0, "T12_SLT_false");
    
    alu_in1=32'hFFFFFFFF; alu_in2=32'd1; alu_ctrl=4'b1001; #2;
    check32(32'd0, 1, 0, "T13_SLTU");
    
    branch=0; jump=1; alu_in1=32'd0; alu_in2=32'd0; alu_ctrl=4'b0000; #2;
    if (pc_src !== 1'b1) begin
        $display("FAIL T14_JAL pc_src not set");
        fail_cnt = fail_cnt + 1;
    end else
        $display("PASS T14_JAL pc_src=1");

    jump=0; alu_opA_sel=1; pc_ex=32'h100; alu_in2=32'h40; alu_ctrl=4'b0000; #2;
    check32(32'h140, 0, 0, "T15_AUIPC");

    alu_opA_sel=0; alu_ctrl=4'b1010; alu_in2=32'h12345000; #2;
    check32(32'h12345000, 0, 0, "T16_LUI");

    jalr_sel=1; jump=1; alu_in1=32'h200; imm_ex=32'h10; alu_ctrl=4'b0000; #2;
    if (branch_target !== 32'h210) begin
        $display("FAIL T17_JALR branch_target: got %08X exp 0x210", branch_target);
        fail_cnt = fail_cnt + 1;
    end else
        $display("PASS T17_JALR branch_target=0x210");

    jump=0; jalr_sel=0; branch=1; funct3_ex=3'b001; alu_in1=32'd5; alu_in2=32'd3; alu_ctrl=4'b0001; #2;
    check32(32'd2, 0, 1, "T18_BNE_taken");

    $display("--- EX Stage: %0d PASS, %0d FAIL ---", pass_cnt, fail_cnt);
    $finish;
end

endmodule
