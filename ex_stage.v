`timescale 1ns/1ps

module ex_stage (
    input  wire [31:0] alu_in1,
    input  wire [31:0] alu_in2,
    input  wire [3:0]  alu_ctrl,
    input  wire [31:0] pc_ex,
    input  wire [31:0] imm_ex,
    input  wire        branch,
    input  wire        jump,
    input  wire	       alu_opA_sel,
    input  wire        jalr_sel,
    input  wire [2:0]  funct3_ex,
    output reg  [31:0] result,
    output wire        zero,
    output wire        pc_src,
    output wire [31:0] branch_target
);

wire [31:0] real_alu_in1 = (alu_opA_sel) ? pc_ex : alu_in1;

always @(*) begin
    case (alu_ctrl)
        4'b0000: result = real_alu_in1 + alu_in2; 
        4'b0001: result = real_alu_in1 - alu_in2;
        4'b0010: result = real_alu_in1 & alu_in2;
        4'b0011: result = real_alu_in1 | alu_in2;
        4'b0100: result = real_alu_in1 ^ alu_in2;
        4'b0101: result = real_alu_in1 << alu_in2[4:0];
        4'b0110: result = real_alu_in1 >> alu_in2[4:0];
        4'b0111: result = $signed(real_alu_in1) >>> alu_in2[4:0];
        4'b1000: result = ($signed(real_alu_in1) < $signed(alu_in2)) ? 32'd1 : 32'd0;
        4'b1001: result = (real_alu_in1 < alu_in2) ? 32'd1 : 32'd0;
        4'b1010: result = alu_in2;
        default: result = 32'b0;
    endcase
end

wire eq_branch = (alu_in1 == alu_in2);
wire lt_signed = ($signed(alu_in1) < $signed(alu_in2));
wire lt_unsign = (alu_in1 < alu_in2);

reg branch_taken;
always @(*) begin
    case (funct3_ex)
        3'b000:  branch_taken = eq_branch;    // BEQ : rs1 == rs2
        3'b001:  branch_taken = ~eq_branch;   // BNE : rs1 != rs2
        3'b100:  branch_taken = lt_signed;    // BLT : rs1 <  rs2 (signed)
        3'b101:  branch_taken = ~lt_signed;   // BGE : rs1 >= rs2 (signed)
        3'b110:  branch_taken = lt_unsign;    // BLTU: rs1 <  rs2 (unsigned)
        3'b111:  branch_taken = ~lt_unsign;   // BGEU: rs1 >= rs2 (unsigned)
        default: branch_taken = 1'b0;
    endcase
end

assign zero  = (result == 32'b0);
assign pc_src       = (branch & branch_taken) | jump;

assign branch_target = (jalr_sel) ? ((alu_in1 + imm_ex) & ~32'd1) : (pc_ex + imm_ex);
endmodule
