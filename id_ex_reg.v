`timescale 1ns/1ps

module id_ex_reg (
    input  wire        clk,clk_en,
    input  wire        rst_n,
    input  wire        flush,
    input  wire [31:0] pc_in,
    input  wire [31:0] pc_plus4_in,
    input  wire [31:0] rs1_data_in,
    input  wire [31:0] rs2_data_in,
    input  wire [31:0] imm_in,
    input  wire        reg_write_in,
    input  wire        alu_src_in,
    input  wire [3:0]  alu_ctrl_in,
    input  wire        mem_read_in,
    input  wire        mem_write_in,
    input  wire        mem_to_reg_in,
    input  wire        branch_in,
    input  wire        jump_in,
    input  wire        alu_opA_sel_in,
    input  wire        jalr_sel_in,
    input  wire        custom_en_in,      
    input  wire [2:0]  custom_op_in,      
    input  wire [2:0]  funct3_in,
    input  wire [4:0]  rs1_addr_in,
    input  wire [4:0]  rs2_addr_in,
    input  wire [4:0]  rd_addr_in,
    output reg  [31:0] pc_out,
    output reg  [31:0] pc_plus4_out,
    output reg  [31:0] rs1_data_out,
    output reg  [31:0] rs2_data_out,
    output reg  [31:0] imm_out,
    output reg         reg_write_out,
    output reg         alu_src_out,
    output reg  [3:0]  alu_ctrl_out,
    output reg         mem_read_out,
    output reg         mem_write_out,
    output reg         mem_to_reg_out,
    output reg         branch_out,
    output reg         jump_out,
    output reg         alu_opA_sel_out,
    output reg         jalr_sel_out,
    output reg         custom_en_out,    
    output reg  [2:0]  custom_op_out,     
    output reg  [2:0]  funct3_out,
    output reg  [4:0]  rs1_addr_out,
    output reg  [4:0]  rs2_addr_out,
    output reg  [4:0]  rd_addr_out
);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        pc_out          <= 32'b0;
        pc_plus4_out    <= 32'b0;
        rs1_data_out    <= 32'b0;
        rs2_data_out    <= 32'b0;
        imm_out         <= 32'b0;
        reg_write_out   <= 1'b0;
        alu_src_out     <= 1'b0;
        alu_ctrl_out    <= 4'b0;
        mem_read_out    <= 1'b0;
        mem_write_out   <= 1'b0;
        mem_to_reg_out  <= 1'b0;
        branch_out      <= 1'b0;
        jump_out        <= 1'b0;
        rs1_addr_out    <= 5'b0;
        rs2_addr_out    <= 5'b0;
        rd_addr_out     <= 5'b0;
        alu_opA_sel_out <= 1'b0;
        jalr_sel_out    <= 1'b0;
        custom_en_out   <= 1'b0;
        custom_op_out   <= 3'b0;
        funct3_out      <= 3'b0;
    end
    else if (clk_en) begin
        if (flush) begin
            pc_out          <= 32'b0;
            pc_plus4_out    <= 32'b0;
            rs1_data_out    <= 32'b0;
            rs2_data_out    <= 32'b0;
            imm_out         <= 32'b0;
            reg_write_out   <= 1'b0;
            alu_src_out     <= 1'b0;
            alu_ctrl_out    <= 4'b0;
            mem_read_out    <= 1'b0;
            mem_write_out   <= 1'b0;
            mem_to_reg_out  <= 1'b0;
            branch_out      <= 1'b0;
            jump_out        <= 1'b0;
            rs1_addr_out    <= 5'b0;
            rs2_addr_out    <= 5'b0;
            rd_addr_out     <= 5'b0;
            alu_opA_sel_out <= 1'b0;
            jalr_sel_out    <= 1'b0;
            custom_en_out   <= 1'b0;     
            custom_op_out   <= 3'b0;
            funct3_out      <= 3'b0;
        end
        else begin
            pc_out          <= pc_in;
            pc_plus4_out    <= pc_plus4_in;
            rs1_data_out    <= rs1_data_in;
            rs2_data_out    <= rs2_data_in;
            imm_out         <= imm_in;
            reg_write_out   <= reg_write_in;
            alu_src_out     <= alu_src_in;
            alu_ctrl_out    <= alu_ctrl_in;
            mem_read_out    <= mem_read_in;
            mem_write_out   <= mem_write_in;
            mem_to_reg_out  <= mem_to_reg_in;
            branch_out      <= branch_in;
            jump_out        <= jump_in;
            rs1_addr_out    <= rs1_addr_in;
            rs2_addr_out    <= rs2_addr_in;
            rd_addr_out     <= rd_addr_in;
            alu_opA_sel_out <= alu_opA_sel_in;
            jalr_sel_out    <= jalr_sel_in;
            custom_en_out   <= custom_en_in;    
            custom_op_out   <= custom_op_in;   
            funct3_out      <= funct3_in;
        end
    end
end

endmodule
