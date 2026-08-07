`timescale 1ns/1ps

module tb_id_stage;

reg        clk, rst_n, reg_write_wb;
reg  [31:0] instr, write_data;
reg  [4:0]  rd_addr_wb;

wire [31:0] rs1_data, rs2_data, imm;
wire        reg_write, alu_src, mem_read, mem_write, mem_to_reg, branch, jump;
wire [3:0]  alu_ctrl;
wire [4:0]  rs1_addr, rs2_addr, rd_addr;

wire        alu_opA_sel, jalr_sel;

id_stage dut (
    .clk          (clk),
    .rst_n        (rst_n),
    .instr        (instr),
    .reg_write_wb (reg_write_wb),
    .rd_addr_wb   (rd_addr_wb),
    .write_data   (write_data),
    .rs1_data     (rs1_data),
    .rs2_data     (rs2_data),
    .imm          (imm),
    .reg_write    (reg_write),
    .alu_src      (alu_src),
    .alu_ctrl     (alu_ctrl),
    .mem_read     (mem_read),
    .mem_write    (mem_write),
    .mem_to_reg   (mem_to_reg),
    .branch       (branch),
    .jump         (jump),

    .alu_opA_sel  (alu_opA_sel),
    .jalr_sel     (jalr_sel),
    
    .rs1_addr     (rs1_addr),
    .rs2_addr     (rs2_addr),
    .rd_addr      (rd_addr)
);

always #5 clk = ~clk;

integer pass_cnt, fail_cnt;

task check_ctrl;
    input exp_reg_write, exp_alu_src, exp_mem_read, exp_mem_write, exp_mem2reg, exp_branch, exp_jump, exp_alu_opA_sel, exp_jalr_sel;
    input [3:0] exp_alu_ctrl;
    input [127:0] label;
    begin
        if ({reg_write, alu_src, mem_read, mem_write, mem_to_reg, branch, jump, alu_opA_sel, jalr_sel, alu_ctrl} !==
            {exp_reg_write, exp_alu_src, exp_mem_read, exp_mem_write, exp_mem2reg, exp_branch, exp_jump, exp_alu_opA_sel, exp_jalr_sel, exp_alu_ctrl}) begin
            $display("FAIL [%0s] ctrl got={RW=%b AS=%b MR=%b MW=%b M2R=%b BR=%b JMP=%b opA=%b JALR=%b ALU=%b}",
                label, reg_write, alu_src, mem_read, mem_write, mem_to_reg, branch, jump, alu_opA_sel, jalr_sel, alu_ctrl);
            $display("         exp={RW=%b AS=%b MR=%b MW=%b M2R=%b BR=%b JMP=%b opA=%b JALR=%b ALU=%b}",
                exp_reg_write, exp_alu_src, exp_mem_read, exp_mem_write, exp_mem2reg, exp_branch, exp_jump, exp_alu_opA_sel, exp_jalr_sel, exp_alu_ctrl);
            fail_cnt = fail_cnt + 1;
        end else begin
            $display("PASS [%0s]", label);
            pass_cnt = pass_cnt + 1;
        end
    end
endtask

initial begin
    clk = 0; rst_n = 0;
    reg_write_wb = 0; rd_addr_wb = 0; write_data = 0;
    instr = 32'b0;
    pass_cnt = 0; fail_cnt = 0;

    repeat(2) @(posedge clk);
    rst_n = 1;
    @(negedge clk);

    $display("--- ID Stage Tests ---");
    
    instr = 32'h002081B3; #1;
    check_ctrl(1,0,0,0,0,0,0, 0,0, 4'b0000, "T1_ADD_Rtype");
    if (rs1_addr !== 5'd1 || rs2_addr !== 5'd2 || rd_addr !== 5'd3)
        $display("FAIL T1 addr: rs1=%0d rs2=%0d rd=%0d", rs1_addr, rs2_addr, rd_addr);
        
    instr = 32'h00500093; #1;
    check_ctrl(1,1,0,0,0,0,0, 0,0, 4'b0000, "T2_ADDI_Itype");
    if (imm !== 32'd5)
        $display("FAIL T2 imm: got %0d exp 5", imm);
    else
        $display("PASS T2_ADDI imm=5");
        
    instr = 32'h00002583; #1;
    check_ctrl(1,1,1,0,1,0,0, 0,0, 4'b0000, "T3_LW");
    
    instr = 32'h00302023; #1;
    check_ctrl(0,1,0,1,0,0,0, 0,0, 4'b0000, "T4_SW");
    
    instr = 32'h00358463; #1;
    check_ctrl(0,0,0,0,0,1,0, 0,0, 4'b0001, "T5_BEQ");
    
    instr = 32'h008007EF; #1;
    check_ctrl(1,0,0,0,0,0,1, 0,0, 4'b0000, "T6_JAL");

    instr = 32'h012345B7; #1; // LUI x11, 0x01234
    check_ctrl(1,1,0,0,0,0,0, 0,0, 4'b1010, "T11_LUI");

    instr = 32'h00001297; #1; // AUIPC x5, 1
    check_ctrl(1,1,0,0,0,0,0, 1,0, 4'b0000, "T12_AUIPC");

    instr = 32'h000080E7; #1; // JALR x1, x1, 0
    check_ctrl(1,1,0,0,0,0,1, 0,1, 4'b0000, "T13_JALR");

    reg_write_wb = 1; rd_addr_wb = 5'd1; write_data = 32'd10;
    @(posedge clk); #1;
    reg_write_wb = 0;
    instr = 32'h002081B3; #1;  // ADD x3, x1, x2 (rs1=x1)
    if (rs1_data !== 32'd10)
        $display("FAIL T7_WB_bypass: rs1_data=%0d exp 10", rs1_data);
    else
        $display("PASS T7_WB_bypass rs1_data=10");

    reg_write_wb = 1; rd_addr_wb = 5'd0; write_data = 32'hFFFF_FFFF;
    @(posedge clk); #1;
    reg_write_wb = 0;
    instr = 32'h00000013; #1; 
    if (rs1_data !== 32'd0)
        $display("FAIL T8_x0_immutable: got %08X", rs1_data);
    else
        $display("PASS T8_x0_immutable");
        
    instr = 32'h40218233; #1;
    check_ctrl(1,0,0,0,0,0,0, 0,0, 4'b0001, "T9_SUB");
    
    instr = 32'h0020F2B3; #1;
    check_ctrl(1,0,0,0,0,0,0, 0,0, 4'b0010, "T10_AND");

    $display("--- ID Stage: %0d PASS, %0d FAIL ---", pass_cnt, fail_cnt);
    $finish;
end

endmodule
